# RunState.gd — minimal autoload for World Conquest seeding.
extends Node

var run_seed: int = 0
## QA / harness: skip interactive deploy pick (instant random capital).
var skip_deploy_pick: bool = false
## Test / spectator: both sides expand via EnemyStrategy (player input muted).
var ai_vs_ai: bool = false
## First-session contextual teach beats; cleared after beat set completes or first battle ends.
var first_run_clarity: bool = true
## World map id from WorldMapCatalog (earth, mars, venus, or mod id).
var world_map_id: String = "earth"
## Economy pack id from EconomyCatalog (default balances).
var economy_pack_id: String = "default"

## True when the player started via Main Menu → Custom World (criteria honored by map gen).
var custom_world: bool = false
## Land/ocean bias: −1.0 more ocean … 0 canonical … +1.0 more land.
## Custom World (procedural): shifts continental noise threshold. Vanilla Play: unused.
var land_bias: float = 0.0
## Multiplier on RESOURCE_BLOBS_PER_TYPE (clamped in map gen; 1.0 = default).
var resource_density: float = 1.0
## Mountain bias: −1.0 flatter … 0 default … +1.0 more mountains (elev / threshold).
var mountain_bias: float = 0.0
## Deploy auto-pick preference: "any" | "west" | "east" (sphere lon hemispheres).
var start_region: String = "any"
## Enemy AI difficulty; −1 = WorldConquestConfig default. 0=Beginner, 1=Medium, 2=Expert.
var ai_difficulty: int = -1


func is_ai_vs_ai() -> bool:
	return ai_vs_ai or OS.get_environment("EOY_AI_VS_AI") == "1"


## Criteria dictionary consumed by WorldConquestMapGenerator.generate(..., criteria).
func map_gen_criteria() -> Dictionary:
	var crit: Dictionary = {
		"land_bias": land_bias,
		"resource_density": resource_density,
		"mountain_bias": mountain_bias,
		"start_region": start_region,
	}
	# Custom World: true procedural continents (not Earth mask + coast bias).
	if custom_world:
		crit["procedural"] = true
	return crit


func reset_custom_world_defaults() -> void:
	custom_world = false
	land_bias = 0.0
	resource_density = 1.0
	mountain_bias = 0.0
	start_region = "any"
	ai_difficulty = -1
	world_map_id = "earth"
