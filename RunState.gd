# RunState.gd — minimal autoload for World Conquest seeding.
extends Node

var run_seed: int = 0
## World map id from WorldMapCatalog (earth, mars, venus, or mod id).
var world_map_id: String = "earth"
## Economy pack id from EconomyCatalog (default balances).
var economy_pack_id: String = "default"
