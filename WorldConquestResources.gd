class_name WorldConquestResources
extends RefCounted

## Owned-deposit mining for World Conquest.
##
## A8 — wallet boundary (WORLD_DATASET_RESOURCE_WALLET):
## - When wallet authority is ON, Rust owns authoritative balances.
## - `tick()` returns *yield deltas* in result.friendly / result.hostile for presentation
##   and for `BattleTerritorySim.apply_resource_tick_delta` — NOT dual balance writes.
## - Godot must NOT treat those arrays as a second wallet: Screen applies deltas via Rust
##   and mirrors the pulled balances into HUD arrays.
## - When wallet authority is OFF (QA/CPU harness only), callers may add deltas to local wallets.
##
## Presentation (R1 visual cut):
## - No haul paths / link ribbons. Owned deposits enter PHASE_MINING immediately.
## - Economy credits from ownership yield_acc; shockwave visuals are cadence-capped (F7).

const BattleTileControlLib := preload("res://BattleTileControl.gd")
const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")

const TYPE_AURELIUM := 0
const TYPE_VERDANTITE := 1
const TYPE_EMBERSTONE := 2

const PHASE_IDLE := "idle"
const PHASE_MINING := "mining"

static var _site_states: Dictionary = {}


static func reset() -> void:
	_site_states.clear()


## A8: true when production live wallet contract is on (balances live in Rust).
static func wallet_authority_active() -> bool:
	return (
		WorldConquestConfigLib.WORLD_DATASET_RESOURCE_WALLET
		and WorldConquestConfigLib.world_dataset_live()
	)


static func _grid_owner_at(grid, idx: int) -> int:
	if grid == null or idx < 0:
		return BattleTileControlLib.OWNER_NEUTRAL
	if grid.has_method("owner_at_index"):
		return int(grid.owner_at_index(idx))
	if "owners" in grid and idx < grid.owners.size():
		return int(grid.owners[idx])
	return BattleTileControlLib.OWNER_NEUTRAL


static func _grid_cell_count(grid) -> int:
	if grid == null:
		return 0
	if grid.has_method("grid_cell_count"):
		return int(grid.grid_cell_count())
	if "owners" in grid:
		return grid.owners.size()
	return 0


## Simulate owned-deposit mining for yield deltas + miner/shockwave presentation.
## result.friendly / result.hostile are per-frame yield *deltas* (not balances).
## Unused structure/home/version args kept for call-site compatibility.
static func tick(
	map_data,
	grid,
	_structures: Array,
	_player_home: Vector2i,
	_enemy_home: Vector2i,
	delta: float,
	_structure_version: int = 0,
	_road_network_version: int = 0,
) -> Dictionary:
	var result := {
		"friendly": [0.0, 0.0, 0.0],
		"hostile": [0.0, 0.0, 0.0],
		"shockwaves": [],
		"sites_dirty": false,
		## Compat aliases for any leftover callers.
		"pulses": [],
		"links_dirty": false,
		"wallet_authority": wallet_authority_active(),
	}
	if map_data == null or grid == null or delta <= 0.0:
		return result
	var deposits: Array = map_data.resource_deposits
	if deposits.is_empty():
		return result

	var sites_dirty: bool = false
	var wave_cap: int = WorldConquestConfigLib.RESOURCE_MAX_VISUAL_SHOCKWAVES
	var period: float = WorldConquestConfigLib.RESOURCE_SHOCKWAVE_PERIOD_SEC
	var cell_n: int = _grid_cell_count(grid)

	for dep: Dictionary in deposits:
		var dep_id: int = int(dep.get("id", -1))
		if dep_id < 0:
			continue
		var gx: int = int(dep.get("gx", 0))
		var gy: int = int(dep.get("gy", 0))
		var idx: int = map_data.cell_index(gx, gy)
		if idx < 0 or idx >= cell_n:
			continue
		var owner: int = _grid_owner_at(grid, idx)
		var team: int = 0
		if owner == BattleTileControlLib.OWNER_FRIENDLY:
			team = BattleTileControlLib.OWNER_FRIENDLY
		elif owner == BattleTileControlLib.OWNER_HOSTILE:
			team = BattleTileControlLib.OWNER_HOSTILE

		var state: Dictionary = _site_state(dep_id)
		if team == 0:
			if not state.is_empty():
				_reset_site(dep_id)
				sites_dirty = true
			continue

		if int(state.get("team", 0)) != team or str(state.get("phase", "")) != PHASE_MINING:
			_reset_site(dep_id)
			state = _site_state(dep_id)
			state["team"] = team
			state["type"] = int(dep.get("type", 0))
			state["gx"] = gx
			state["gy"] = gy
			state["size"] = int(dep.get("size", 1))
			state["yield_per_sec"] = float(dep.get("yield_per_sec", 1.0))
			state["yield_acc"] = 0.0
			state["phase"] = PHASE_MINING
			# Stagger so mines don't flash in sync (dep_id * 0.37 mod period).
			state["pulse_t"] = fmod(float(dep_id) * 0.37, period)
			sites_dirty = true
		else:
			state["type"] = int(dep.get("type", 0))
			state["gx"] = gx
			state["gy"] = gy
			state["size"] = int(dep.get("size", 1))
			state["yield_per_sec"] = float(dep.get("yield_per_sec", 1.0))

		# Full economy credit while owned — independent of shockwave visual budget.
		var yield_rate: float = float(state.get("yield_per_sec", 1.0))
		var acc: float = float(state.get("yield_acc", 0.0)) + yield_rate * delta
		var credited: float = 0.0
		while acc >= 1.0:
			credited += 1.0
			acc -= 1.0
		state["yield_acc"] = acc
		if credited > 0.0:
			var wallet: Array = (
				result.friendly if team == BattleTileControlLib.OWNER_FRIENDLY else result.hostile
			)
			wallet[int(state.get("type", 0))] += credited

		# Shockwave cadence (~2 s) with stagger; skip emit when over visual cap.
		var pulse_t: float = float(state.get("pulse_t", 0.0)) + delta
		if pulse_t >= period:
			pulse_t = fmod(pulse_t, period)
			if result.shockwaves.size() < wave_cap:
				var wave := {
					"gx": gx,
					"gy": gy,
					"type": int(state.get("type", 0)),
					"team": team,
					"size": int(state.get("size", 1)),
					"t": 0.0,
				}
				result.shockwaves.append(wave)
		state["pulse_t"] = pulse_t

	result.sites_dirty = sites_dirty
	result.links_dirty = sites_dirty
	result.pulses = result.shockwaves
	return result


static func site_states() -> Dictionary:
	return _site_states


static func _site_state(dep_id: int) -> Dictionary:
	var key: String = "dep_%d" % dep_id
	if not _site_states.has(key):
		_site_states[key] = {}
	return _site_states[key]


static func _reset_site(dep_id: int) -> void:
	_site_states.erase("dep_%d" % dep_id)
