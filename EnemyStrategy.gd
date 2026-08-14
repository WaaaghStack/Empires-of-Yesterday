class_name EnemyStrategy
extends RefCounted

## Pure decision layer for hostile / AI-vs-AI expansion. Returns prioritized placement intents;
## callers execute via existing placement + builder job queues.
##
## Design lock A13/F1 (updated): AI places **outposts + barracks + hangar** for both teams
## (AI vs AI / human vs AI). Still **no bridges** (R1).
## R1 placeability: candidates/scores require claimable land (beachhead / air-strike opened),
## reject opponent-owned; barracks/hangar heavily prefer self-owned claimable.
## Planner caps + supply/mineral reserves + place cooldown are primary. R1 instant ACTIVE
## makes CONNECTING-count gates useless — Screen must not stall on connecting counts.
## Outposts are hard-capped and tile-gated so the AI cannot out-click a human.
##
## B1 pathfind policy (Screen must honor via helpers below):
## - Always try budgeted/capped route first (`prefer_budgeted_route` / allow_astar=false).
## - Full A* only when `route_allow_full_astar` says so (rate-limited, hard expand budget).
## - Never enable hover A* from this module (B9 stays false in Config / Screen hover path).
## - After budgeted + full A* miss: Screen may retry with allow_standalone=true (R1 last resort).
## - W3: wire `_drain_enemy_ai_queue` to these APIs and REMOVE unbounded allow_astar=true fallback.

## Last `plan_actions` empty-reason (for throttled soak diagnostics).
static var last_empty_reason: String = ""

const CFG := preload("res://WorldConquestConfig.gd")
const EconomyLib := preload("res://EconomyLib.gd")
const OutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const EarthMapGeneratorLib := preload("res://EarthMapGenerator.gd")
const BattleTerritorySimLib := preload("res://BattleTerritorySim.gd")
const ResourceLib := preload("res://WorldConquestResources.gd")

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
	# Keep kind as planned (spawner / barracks / hangar). R1: still no bridges.
	return out


## --- Planner ---------------------------------------------------------------------

static func plan_actions(snapshot: Dictionary) -> Array[Dictionary]:
	last_empty_reason = ""
	var map_data = snapshot.get("map_data")
	if map_data == null:
		last_empty_reason = "no_map"
		return []
	var difficulty: int = int(snapshot.get("difficulty", Difficulty.MEDIUM))
	# Team-aware roles (defaults preserve hostile-only enemy AI).
	var self_owner: int = int(snapshot.get("self_owner", BattleTileControlLib.OWNER_HOSTILE))
	var opponent_owner: int = int(
		snapshot.get("opponent_owner", BattleTileControlLib.OWNER_FRIENDLY)
	)
	var self_home: Vector2i = snapshot.get(
		"self_home", snapshot.get("enemy_home", Vector2i(-1, -1))
	)
	var opponent_home: Vector2i = snapshot.get(
		"opponent_home", snapshot.get("player_home", Vector2i(-1, -1))
	)
	if self_home.x < 0 or opponent_home.x < 0:
		last_empty_reason = "missing_homes"
		return []
	var structures: Array = snapshot.get("structures", [])
	var owners: PackedByteArray = snapshot.get("owners", PackedByteArray())
	if owners.is_empty():
		last_empty_reason = "no_owners"
		return []
	# R1 placeability: same claimable mask the Screen precheck uses (beachhead / air-strike opened).
	var claimable: PackedByteArray = snapshot.get("claimable", PackedByteArray())
	var self_supply: float = float(
		snapshot.get("self_supply", snapshot.get("enemy_supply", 0.0))
	)
	var self_resources: Array = snapshot.get("self_resources", [0.0, 0.0, 0.0])
	var self_au: float = 0.0
	var self_em: float = 0.0
	if self_resources.size() > ResourceLib.TYPE_AURELIUM:
		self_au = float(self_resources[ResourceLib.TYPE_AURELIUM])
	if self_resources.size() > ResourceLib.TYPE_EMBERSTONE:
		self_em = float(self_resources[ResourceLib.TYPE_EMBERSTONE])
	var outpost_cost: float = EconomyLib.supply_cost(OutpostBuildLib.KIND_SPAWNER)
	var barracks_cost: float = EconomyLib.supply_cost(OutpostBuildLib.KIND_BARRACKS)
	var hangar_cost: float = EconomyLib.supply_cost(OutpostBuildLib.KIND_HANGAR)
	if self_supply < outpost_cost and self_supply < barracks_cost and self_supply < hangar_cost:
		last_empty_reason = "supply_below_any_build_cost"
		return []
	# R1: do NOT gate on connecting_self — instant ACTIVE makes CONNECTING counts stale/stuck.

	var sources: Array[Vector2i] = OutpostBuildLib.operational_sources(
		structures, self_home, map_data, self_owner
	)
	if sources.is_empty():
		last_empty_reason = "no_sources"
		return []

	var own_spawners: int = _count_kind(structures, self_owner, OutpostBuildLib.KIND_SPAWNER)
	var own_barracks: int = _count_kind(structures, self_owner, OutpostBuildLib.KIND_BARRACKS)
	var own_hangars: int = _count_kind(structures, self_owner, OutpostBuildLib.KIND_HANGAR)
	var self_tiles: int = int(snapshot.get("self_tiles", -1))
	if self_tiles < 0:
		if self_owner == BattleTileControlLib.OWNER_HOSTILE:
			self_tiles = int(snapshot.get("hostile_tiles", 0))
		else:
			self_tiles = int(snapshot.get("friendly_tiles", 0))
	var max_outposts: int = _max_outposts(difficulty)
	var need_outposts: bool = own_spawners < CFG.ENEMY_AI_MIN_OUTPOSTS_BEFORE_MILITARY
	var allow_military: bool = not need_outposts
	var outpost_need: float = outpost_cost + float(CFG.ENEMY_AI_OUTPOST_RESERVE) * float(own_spawners)
	var allow_outpost: bool = (
		own_spawners < max_outposts
		and self_supply >= outpost_need
		and (
			own_spawners <= 0
			or self_tiles >= own_spawners * CFG.ENEMY_AI_TILES_PER_OUTPOST
		)
	)
	var allow_barracks: bool = (
		allow_military
		and own_barracks < CFG.ENEMY_AI_MAX_BARRACKS
		and self_supply >= barracks_cost + float(CFG.ENEMY_AI_SUPPLY_RESERVE)
		and self_au >= CFG.ENEMY_AI_BARRACKS_MIN_AU
	)
	var allow_hangar: bool = (
		allow_military
		and own_barracks >= 1
		and own_hangars < CFG.ENEMY_AI_MAX_HANGARS
		and self_supply >= hangar_cost + float(CFG.ENEMY_AI_SUPPLY_RESERVE)
		and self_em >= CFG.ENEMY_AI_HANGAR_MIN_EM
	)

	var vision: int = _vision_radius(difficulty)
	var stride: int = CFG.ENEMY_AI_FRONTIER_SAMPLE_STRIDE
	var max_candidates: int = CFG.ENEMY_AI_MAX_CANDIDATES
	var candidates: Array[Vector2i] = _collect_candidates(
		map_data,
		owners,
		claimable,
		sources,
		self_home,
		opponent_home,
		vision,
		stride,
		max_candidates,
		difficulty,
		opponent_owner,
	)
	if candidates.is_empty():
		last_empty_reason = "candidates_empty"
		return []

	var scored: Array[Dictionary] = []
	var spacing_rejects: int = 0
	var military_spacing_rejects: int = 0
	for cand: Vector2i in candidates:
		if allow_outpost:
			var outpost_score: float = _score_outpost_cell(
				map_data,
				owners,
				claimable,
				cand,
				self_home,
				opponent_home,
				structures,
				difficulty,
				self_owner,
				opponent_owner,
			)
			if need_outposts and outpost_score > 0.0:
				outpost_score += 8.0
			if outpost_score > 0.0:
				scored.append(decorate_action_path_policy({
					"kind": OutpostBuildLib.KIND_SPAWNER,
					"target": cand,
					"score": outpost_score,
				}))
			elif not _spacing_ok_for_kind(
				map_data, cand, structures, OutpostBuildLib.KIND_SPAWNER
			):
				spacing_rejects += 1
		if allow_barracks:
			var barracks_score: float = _score_barracks_cell(
				map_data, owners, claimable, cand, self_home, structures, self_owner, opponent_owner
			)
			if barracks_score > 0.0:
				scored.append(decorate_action_path_policy({
					"kind": OutpostBuildLib.KIND_BARRACKS,
					"target": cand,
					"score": barracks_score,
				}))
			elif not _spacing_ok_for_kind(
				map_data, cand, structures, OutpostBuildLib.KIND_BARRACKS
			):
				military_spacing_rejects += 1
		if allow_hangar:
			var hangar_score: float = _score_hangar_cell(
				map_data, owners, claimable, cand, self_home, structures, self_owner, opponent_owner
			)
			if hangar_score > 0.0:
				scored.append(decorate_action_path_policy({
					"kind": OutpostBuildLib.KIND_HANGAR,
					"target": cand,
					"score": hangar_score,
				}))
			elif not _spacing_ok_for_kind(
				map_data, cand, structures, OutpostBuildLib.KIND_HANGAR
			):
				military_spacing_rejects += 1

	if scored.is_empty():
		if (
			spacing_rejects >= candidates.size()
			and candidates.size() > 0
			and not allow_barracks
			and not allow_hangar
		):
			last_empty_reason = "all_candidates_spacing"
		elif (
			allow_barracks
			and military_spacing_rejects >= candidates.size()
			and candidates.size() > 0
		):
			last_empty_reason = "all_candidates_military_spacing"
		elif self_supply < outpost_need and not allow_barracks and not allow_hangar:
			last_empty_reason = "supply_or_military_gated"
		else:
			last_empty_reason = (
				"scored_empty cand=%d spacing_rej=%d mil_sp_rej=%d mil_ok=%s brk=%s hgr=%s"
				% [
					candidates.size(),
					spacing_rejects,
					military_spacing_rejects,
					str(allow_military),
					str(allow_barracks),
					str(allow_hangar),
				]
			)
		return []

	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
	)

	var max_actions: int = mini(CFG.ENEMY_AI_MAX_ACTIONS_PER_PLAN, scored.size())
	var out: Array[Dictionary] = []
	for i in range(max_actions):
		out.append(scored[i])
	return out


## Snapshot fields for throttled empty-plan soak logs (does not re-plan).
static func empty_plan_diag(snapshot: Dictionary) -> Dictionary:
	var structures: Array = snapshot.get("structures", [])
	var self_owner: int = int(snapshot.get("self_owner", BattleTileControlLib.OWNER_HOSTILE))
	var self_resources: Array = snapshot.get("self_resources", [0.0, 0.0, 0.0])
	var self_au: float = 0.0
	var self_em: float = 0.0
	if self_resources.size() > ResourceLib.TYPE_AURELIUM:
		self_au = float(self_resources[ResourceLib.TYPE_AURELIUM])
	if self_resources.size() > ResourceLib.TYPE_EMBERSTONE:
		self_em = float(self_resources[ResourceLib.TYPE_EMBERSTONE])
	return {
		"reason": last_empty_reason,
		"supply": float(snapshot.get("self_supply", snapshot.get("enemy_supply", 0.0))),
		"own_spawners": _count_kind(structures, self_owner, OutpostBuildLib.KIND_SPAWNER),
		"own_barracks": _count_kind(structures, self_owner, OutpostBuildLib.KIND_BARRACKS),
		"own_hangars": _count_kind(structures, self_owner, OutpostBuildLib.KIND_HANGAR),
		"self_au": self_au,
		"self_em": self_em,
		"connecting": int(
			snapshot.get("connecting_self", snapshot.get("connecting_hostile", 0))
		),
	}


static func _count_kind(structures: Array, self_owner: int, kind: String) -> int:
	var n: int = 0
	for st: Dictionary in structures:
		if int(st.get("team", BattleTileControlLib.OWNER_FRIENDLY)) != self_owner:
			continue
		if str(st.get("kind", "")) != kind:
			continue
		n += 1
	return n


## Empty claimable = legacy snapshot (treat all land as claimable). Otherwise match Screen precheck.
static func _cell_claimable(claimable: PackedByteArray, idx: int) -> bool:
	if claimable.is_empty():
		return true
	if idx < 0 or idx >= claimable.size():
		return false
	return claimable[idx] != 0


## Placeable for self: claimable land that is not opponent-owned (self or neutral OK).
static func _placeable_for_self(
	owners: PackedByteArray,
	claimable: PackedByteArray,
	idx: int,
	opponent_owner: int,
) -> bool:
	if idx < 0 or idx >= owners.size():
		return false
	if int(owners[idx]) == opponent_owner:
		return false
	return _cell_claimable(claimable, idx)


static func _collect_candidates(
	map_data,
	owners: PackedByteArray,
	claimable: PackedByteArray,
	sources: Array[Vector2i],
	self_home: Vector2i,
	opponent_home: Vector2i,
	vision: int,
	stride: int,
	max_count: int,
	difficulty: int,
	opponent_owner: int = BattleTileControlLib.OWNER_FRIENDLY,
) -> Array[Vector2i]:
	if map_data.sphere_mode:
		return _collect_candidates_sphere(
			map_data,
			owners,
			claimable,
			sources,
			self_home,
			opponent_home,
			vision,
			stride,
			max_count,
			difficulty,
			opponent_owner,
		)
	var w: int = map_data.grid_width
	var h: int = map_data.grid_height
	var seen: Dictionary = {}
	var out: Array[Vector2i] = []
	var toward: Vector2i = _norm_dir(opponent_home - self_home)

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
				if not _placeable_for_self(owners, claimable, idx, opponent_owner):
					continue
				out.append(cand)

	if out.is_empty() and difficulty == Difficulty.BEGINNER:
		# Beginner: small jitter around home when no frontier found yet.
		var rng := RandomNumberGenerator.new()
		rng.seed = int(map_data.map_seed) ^ 0xEAEA
		for _i in range(8):
			var gx: int = clampi(
				self_home.x + rng.randi_range(-vision, vision), 0, w - 1
			)
			var gy: int = clampi(
				self_home.y + rng.randi_range(-vision / 2, vision / 2), 0, h - 1
			)
			if not map_data.is_land_cell(gx, gy):
				continue
			var idx2: int = map_data.cell_index(gx, gy)
			if not _placeable_for_self(owners, claimable, idx2, opponent_owner):
				continue
			out.append(Vector2i(gx, gy))
			if out.size() >= mini(8, max_count):
				break
	return out


static func _collect_candidates_sphere(
	map_data,
	owners: PackedByteArray,
	claimable: PackedByteArray,
	sources: Array[Vector2i],
	self_home: Vector2i,
	_opponent_home: Vector2i,
	vision: int,
	stride: int,
	max_count: int,
	difficulty: int,
	opponent_owner: int = BattleTileControlLib.OWNER_FRIENDLY,
) -> Array[Vector2i]:
	var n: int = map_data.cell_count
	var seen: Dictionary = {}
	var out: Array[Vector2i] = []
	var dist: PackedInt32Array = PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	var queue: Array[int] = []
	# Sphere: denser ring sample so post-first-outpost spacing still leaves viable rings.
	var sample_stride: int = maxi(2, stride / 2)
	var sample_max: int = maxi(max_count, max_count * 2)
	for src: Vector2i in sources:
		var cid: int = src.x
		if cid < 0 or cid >= n or dist[cid] >= 0:
			continue
		# Seeds must be claimable placeable land; otherwise BFS floods ocean → foreign dirt.
		if not map_data.is_land_cell(cid, 0):
			continue
		if not _cell_claimable(claimable, cid):
			continue
		dist[cid] = 0
		queue.append(cid)
	var qi: int = 0
	while qi < queue.size() and out.size() < sample_max:
		var cur: int = queue[qi]
		qi += 1
		var cur_d: int = dist[cur]
		if cur_d > vision:
			continue
		if cur_d > 0 and cur_d % sample_stride == 0:
			if map_data.is_land_cell(cur, 0):
				if _placeable_for_self(owners, claimable, cur, opponent_owner):
					var key: String = str(cur)
					if not seen.has(key):
						seen[key] = true
						out.append(Vector2i(cur, 0))
		for nbr in map_data.get_neighbors(cur):
			if nbr < 0 or nbr >= n:
				continue
			var nd: int = cur_d + 1
			if nd > vision or dist[nbr] >= 0:
				continue
			# Stay on the opened beachhead: only walk claimable land (no ocean hop to islands).
			if not map_data.is_land_cell(nbr, 0):
				continue
			if not _cell_claimable(claimable, nbr):
				continue
			dist[nbr] = nd
			queue.append(nbr)
	# Any difficulty: if rings are empty / all ocean / owned, jitter near visited land.
	if out.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = int(map_data.map_seed) ^ 0xEAEA ^ int(difficulty)
		var fallback: Array[int] = []
		if self_home.x >= 0 and self_home.x < n and _cell_claimable(claimable, self_home.x):
			fallback.append(self_home.x)
		for src2: Vector2i in sources:
			if src2.x >= 0 and src2.x < n and _cell_claimable(claimable, src2.x):
				fallback.append(src2.x)
		for _i in range(24):
			if fallback.is_empty() or out.size() >= mini(16, sample_max):
				break
			var pick: int = fallback[rng.randi_range(0, fallback.size() - 1)]
			for nbr2 in map_data.get_neighbors(pick):
				if nbr2 < 0 or nbr2 >= n:
					continue
				# Accept unvisited neighbors within vision, or any land neighbor if BFS starved.
				var d2: int = dist[nbr2]
				if d2 > vision and d2 >= 0:
					continue
				if not map_data.is_land_cell(nbr2, 0):
					continue
				if not _placeable_for_self(owners, claimable, nbr2, opponent_owner):
					continue
				var key2: String = str(nbr2)
				if seen.has(key2):
					continue
				seen[key2] = true
				out.append(Vector2i(nbr2, 0))
				fallback.append(nbr2)
				if out.size() >= mini(16, sample_max):
					break
	return out


static func _score_outpost_cell(
	map_data,
	owners: PackedByteArray,
	claimable: PackedByteArray,
	cand: Vector2i,
	self_home: Vector2i,
	opponent_home: Vector2i,
	structures: Array,
	difficulty: int,
	self_owner: int = BattleTileControlLib.OWNER_HOSTILE,
	opponent_owner: int = BattleTileControlLib.OWNER_FRIENDLY,
) -> float:
	var idx: int = map_data.cell_index(cand.x, cand.y)
	if not _placeable_for_self(owners, claimable, idx, opponent_owner):
		return 0.0
	var owner: int = int(owners[idx])
	if not _spacing_ok_for_kind(map_data, cand, structures, OutpostBuildLib.KIND_SPAWNER):
		return 0.0

	var score: float = 0.0
	# Prefer consolidating on self-owned claimable; still score neutral claimable frontier.
	if owner == self_owner:
		score += 16.0
	elif owner == BattleTileControlLib.OWNER_NEUTRAL:
		score += 10.0
	else:
		return 0.0

	if _has_owner_neighbor(owners, map_data, cand, self_owner):
		score += 14.0
	if _has_owner_neighbor(owners, map_data, cand, opponent_owner):
		score += 6.0 * _contest_weight(difficulty)

	var dist_opponent: float = _geo_distance(map_data, cand, opponent_home)
	var dist_self: float = _geo_distance(map_data, cand, self_home)
	score += _advance_weight(difficulty) * maxf(0.0, 48.0 - dist_opponent * 0.35)
	score -= dist_self * 0.08
	return score


static func _score_barracks_cell(
	map_data,
	owners: PackedByteArray,
	claimable: PackedByteArray,
	cand: Vector2i,
	self_home: Vector2i,
	structures: Array,
	self_owner: int,
	opponent_owner: int,
) -> float:
	var idx: int = map_data.cell_index(cand.x, cand.y)
	if not _placeable_for_self(owners, claimable, idx, opponent_owner):
		return 0.0
	var owner: int = int(owners[idx])
	if not _spacing_ok_for_kind(map_data, cand, structures, OutpostBuildLib.KIND_BARRACKS):
		return 0.0
	# Military behind the fluid front: heavily prefer self-owned claimable.
	var score: float = 0.0
	if owner == self_owner:
		score += 42.0
	elif owner == BattleTileControlLib.OWNER_NEUTRAL:
		score += 2.0
	else:
		return 0.0
	if _has_owner_neighbor(owners, map_data, cand, self_owner):
		score += 8.0
	var dist_self: float = _geo_distance(map_data, cand, self_home)
	score += maxf(0.0, 24.0 - dist_self * 0.4)
	return score


static func _score_hangar_cell(
	map_data,
	owners: PackedByteArray,
	claimable: PackedByteArray,
	cand: Vector2i,
	self_home: Vector2i,
	structures: Array,
	self_owner: int,
	opponent_owner: int,
) -> float:
	var idx: int = map_data.cell_index(cand.x, cand.y)
	if not _placeable_for_self(owners, claimable, idx, opponent_owner):
		return 0.0
	var owner: int = int(owners[idx])
	if not _spacing_ok_for_kind(map_data, cand, structures, OutpostBuildLib.KIND_HANGAR):
		return 0.0
	var score: float = 0.0
	if owner == self_owner:
		score += 38.0
	elif owner == BattleTileControlLib.OWNER_NEUTRAL:
		score += 1.5
	else:
		return 0.0
	if _has_owner_neighbor(owners, map_data, cand, self_owner):
		score += 6.0
	var dist_self: float = _geo_distance(map_data, cand, self_home)
	score += maxf(0.0, 20.0 - dist_self * 0.35)
	# Slightly below barracks so hangars tend to follow after barracks when scores tie-break.
	score -= 1.0
	return score


## Sphere: angular distance (radians scaled ~cells); rect: Euclidean cell distance.
static func _geo_distance(map_data, a: Vector2i, b: Vector2i) -> float:
	if map_data != null and map_data.sphere_mode:
		if (
			a.x < 0
			or b.x < 0
			or a.x >= map_data.cell_positions.size()
			or b.x >= map_data.cell_positions.size()
		):
			return 9999.0
		var pa: Vector3 = map_data.cell_positions[a.x].normalized()
		var pb: Vector3 = map_data.cell_positions[b.x].normalized()
		var ang: float = acos(clampf(pa.dot(pb), -1.0, 1.0))
		var cell_ang: float = sqrt(TAU * 2.0 / maxf(1.0, float(map_data.cell_count)))
		return ang / maxf(cell_ang, 1e-6)
	return float(a.distance_to(b))


static func _spacing_ok(map_data, cand: Vector2i, structures: Array) -> bool:
	return _spacing_ok_for_kind(map_data, cand, structures, OutpostBuildLib.KIND_SPAWNER)


## Kind-aware structure spacing.
## - Spawners: ENEMY_AI_OUTPOST_SPACING_CELLS (wider than the player's min 6).
## - Barracks/hangar: soft ENEMY_AI_MILITARY_SPACING_CELLS vs all (incl. outposts) so small
##   beachheads can host military next to spawners; still prevents stacking.
static func _max_outposts(difficulty: int) -> int:
	var cap: int = CFG.ENEMY_AI_MAX_OUTPOSTS
	match difficulty:
		Difficulty.BEGINNER:
			return maxi(4, cap - 3)
		Difficulty.EXPERT:
			return cap + 2
	return cap


static func _min_spacing_cells_for_kind(place_kind: String) -> int:
	if (
		place_kind == OutpostBuildLib.KIND_BARRACKS
		or place_kind == OutpostBuildLib.KIND_HANGAR
	):
		return maxi(2, int(CFG.ENEMY_AI_MILITARY_SPACING_CELLS))
	return maxi(CFG.MIN_SPAWNER_SPACING_CELLS, int(CFG.ENEMY_AI_OUTPOST_SPACING_CELLS))


static func _spacing_ok_for_kind(
	map_data, cand: Vector2i, structures: Array, kind: String
) -> bool:
	var min_d: int = _min_spacing_cells_for_kind(kind)
	for st: Dictionary in structures:
		var bx: int = int(st.get("gx", 0))
		var by: int = int(st.get("gy", 0))
		if map_data != null and map_data.sphere_mode:
			if (
				cand.x < 0
				or bx < 0
				or cand.x >= map_data.cell_positions.size()
				or bx >= map_data.cell_positions.size()
			):
				continue
			var pa: Vector3 = map_data.cell_positions[cand.x].normalized()
			var pb: Vector3 = map_data.cell_positions[bx].normalized()
			var ang: float = acos(clampf(pa.dot(pb), -1.0, 1.0))
			var cell_ang: float = sqrt(TAU * 2.0 / maxf(1.0, float(map_data.cell_count)))
			if ang < cell_ang * float(min_d):
				return false
		else:
			var dx: int = cand.x - bx
			var dy: int = cand.y - by
			if dx * dx + dy * dy < min_d * min_d:
				return false
	return true


static func _has_owner_neighbor(
	owners: PackedByteArray, map_data, cell: Vector2i, want_owner: int
) -> bool:
	if map_data.sphere_mode:
		for nbr in map_data.get_neighbors(cell.x):
			if nbr >= 0 and nbr < owners.size() and int(owners[nbr]) == want_owner:
				return true
		return false
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
		"claimable": tc.claimable_mask if tc != null else PackedByteArray(),
		"enemy_home": map_data.enemy_home_grid,
		"player_home": map_data.player_home_grid,
		"friendly_tiles": tc.friendly_tiles if tc != null else 0,
		"hostile_tiles": tc.hostile_tiles if tc != null else 0,
		"claimable_tiles": sim.claimable_tiles,
		"enemy_supply": float(CFG.STARTING_SUPPLY),
		"self_resources": [0.0, 0.0, 0.0],
		"difficulty": Difficulty.MEDIUM,
		"connecting_hostile": 0,
	}
	var actions: Array[Dictionary] = plan_actions(snap)
	if actions.is_empty():
		return {"ok": false, "detail": "plan_actions returned empty on medium snapshot"}
	var saw_outpost: bool = false
	for a: Dictionary in actions:
		var kind: String = str(a.get("kind", ""))
		if kind == "":
			return {"ok": false, "detail": "action missing kind"}
		# Allowed kinds: outpost / barracks / hangar (no bridges). Legacy snapshot should
		# still prefer outposts when military gates are not met.
		if (
			kind != OutpostBuildLib.KIND_SPAWNER
			and kind != OutpostBuildLib.KIND_BARRACKS
			and kind != OutpostBuildLib.KIND_HANGAR
		):
			return {"ok": false, "detail": "unexpected kind=%s (bridges forbidden)" % kind}
		if kind == OutpostBuildLib.KIND_SPAWNER:
			saw_outpost = true
		var tgt: Vector2i = a.get("target", Vector2i(-1, -1))
		if tgt.x < 0:
			return {"ok": false, "detail": "action missing target"}
		if not bool(a.get("prefer_budgeted", false)):
			return {"ok": false, "detail": "action missing prefer_budgeted policy"}
		if int(a.get("path_tier", -1)) != PathTier.BUDGETED:
			return {"ok": false, "detail": "planned actions must start at BUDGETED path tier"}
		if int(a.get("max_path_expand", 0)) != max_path_expand_for_ai():
			return {"ok": false, "detail": "action max_path_expand mismatch"}
	if not saw_outpost:
		return {"ok": false, "detail": "legacy snapshot expected at least one outpost action"}
	return {
		"ok": true,
		"detail": "actions=%d expand_cap=%d" % [actions.size(), max_path_expand_for_ai()],
	}
