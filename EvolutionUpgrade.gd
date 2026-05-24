class_name EvolutionUpgrade
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var pool: String = "Firepower"
@export var tags: Array[String] = []
@export var tier: int = 1
@export var squad_wide: bool = false
@export var synergy_requires: Array[String] = []
@export var description: String = ""
@export var damage_mult: float = 1.0
@export var fire_rate_mult: float = 1.0
@export var health_mult: float = 1.0
@export var defense_bonus: int = 0
@export var speed_mult: float = 1.0
@export var chain_damage_pct: float = 0.0
@export var biomass_on_kill: int = 0
@export var orbital_charge_bonus: float = 0.0


static func get_catalog() -> Array[EvolutionUpgrade]:
	var upgrades: Array[EvolutionUpgrade] = []
	for spec in _UPGRADE_SPECS:
		var u: EvolutionUpgrade = load("res://EvolutionUpgrade.gd").new()
		u.id = str(spec.get("id", ""))
		u.display_name = str(spec.get("display_name", u.id))
		u.pool = str(spec.get("pool", "Firepower"))
		u.tags = _to_string_array(spec.get("tags", []))
		u.tier = int(spec.get("tier", 1))
		u.squad_wide = spec.get("squad_wide", false)
		u.synergy_requires = _to_string_array(spec.get("synergy_requires", []))
		u.description = str(spec.get("description", ""))
		u.damage_mult = float(spec.get("damage_mult", 1.0))
		u.fire_rate_mult = float(spec.get("fire_rate_mult", 1.0))
		u.health_mult = float(spec.get("health_mult", 1.0))
		u.defense_bonus = int(spec.get("defense_bonus", 0))
		u.speed_mult = float(spec.get("speed_mult", 1.0))
		u.chain_damage_pct = float(spec.get("chain_damage_pct", 0.0))
		u.biomass_on_kill = int(spec.get("biomass_on_kill", 0))
		u.orbital_charge_bonus = float(spec.get("orbital_charge_bonus", 0.0))
		upgrades.append(u)
	return upgrades


static func get_by_id(upgrade_id: String) -> EvolutionUpgrade:
	for upgrade in get_catalog():
		if upgrade.id == upgrade_id:
			return upgrade
	return null


static func roll_choices(board, count: int = 3, rng: RandomNumberGenerator = null) -> Array:
	var local_rng := rng if rng else RandomNumberGenerator.new()
	if rng == null:
		local_rng.randomize()
	var candidates: Array[EvolutionUpgrade] = []
	for upgrade in get_catalog():
		if board and board.has_upgrade(upgrade.id):
			continue
		if board and not upgrade.synergy_requires.is_empty():
			var ok := true
			for req in upgrade.synergy_requires:
				if not board.has_tag(req):
					ok = false
					break
			if not ok:
				continue
		candidates.append(upgrade)
	if candidates.is_empty():
		return []
	candidates.shuffle()
	var picks: Array = []
	for i in range(mini(count, candidates.size())):
		picks.append(candidates[i])
	return picks


static func _to_string_array(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	if raw is Array:
		for v in raw:
			result.append(str(v))
	return result


const _UPGRADE_SPECS: Array[Dictionary] = [
	# Chain 1: PlasmaRepeater → OverchargeModule → BiomassRecycler → AdaptiveResonance
	{"id": "plasma_repeater", "display_name": "Plasma Repeater", "pool": "Firepower", "tags": ["energy", "plasma"], "tier": 1, "damage_mult": 1.12, "fire_rate_mult": 1.05, "description": "+12% damage, energy tag."},
	{"id": "overcharge_module", "display_name": "Overcharge Module", "pool": "Tech", "tags": ["energy", "overcharge"], "tier": 2, "synergy_requires": ["plasma"], "damage_mult": 1.18, "fire_rate_mult": 1.1, "description": "Synergy: plasma → burst overcharge."},
	{"id": "biomass_recycler", "display_name": "Biomass Recycler", "pool": "Bio", "tags": ["bio", "recycler"], "tier": 2, "synergy_requires": ["overcharge"], "biomass_on_kill": 2, "description": "Synergy: overcharge → biomass on kill."},
	{"id": "adaptive_resonance", "display_name": "Adaptive Resonance", "pool": "Tech", "tags": ["energy", "adaptive"], "tier": 3, "synergy_requires": ["recycler"], "damage_mult": 1.25, "chain_damage_pct": 0.35, "description": "Synergy capstone: chain damage on kills."},
	# Chain 2: ReinforcedPlate → ReactiveArmor → EchoShield → YesterdaysMantle
	{"id": "reinforced_plate", "display_name": "Reinforced Plate", "pool": "Defense", "tags": ["armor", "kinetic"], "tier": 1, "defense_bonus": 3, "health_mult": 1.08, "description": "+DEF, +HP."},
	{"id": "reactive_armor", "display_name": "Reactive Armor", "pool": "Defense", "tags": ["armor", "reactive"], "tier": 2, "synergy_requires": ["armor"], "defense_bonus": 4, "health_mult": 1.1, "description": "Synergy: armor → reactive plating."},
	{"id": "echo_shield", "display_name": "Echo Shield", "pool": "Bio", "tags": ["echo", "shield"], "tier": 2, "synergy_requires": ["reactive"], "defense_bonus": 3, "orbital_charge_bonus": 5.0, "description": "Synergy: reactive → echo shielding."},
	{"id": "yesterdays_mantle", "display_name": "Yesterday's Mantle", "pool": "Bio", "tags": ["echo", "mantle"], "tier": 3, "synergy_requires": ["echo"], "squad_wide": true, "health_mult": 1.15, "defense_bonus": 5, "description": "Synergy capstone: squad-wide mantle."},
	# Chain 3: StimInjector → NeuralUplink → PredatorInstinct
	{"id": "stim_injector", "display_name": "Stim Injector", "pool": "Mobility", "tags": ["stim", "injector"], "tier": 1, "speed_mult": 1.1, "fire_rate_mult": 1.05, "description": "+speed, +fire rate."},
	{"id": "neural_uplink", "display_name": "Neural Uplink", "pool": "Tech", "tags": ["neural", "uplink"], "tier": 2, "synergy_requires": ["stim"], "damage_mult": 1.14, "chain_damage_pct": 0.15, "description": "Synergy: stim → neural targeting."},
	{"id": "predator_instinct", "display_name": "Predator Instinct", "pool": "Swarm", "tags": ["predator", "instinct"], "tier": 3, "synergy_requires": ["neural"], "damage_mult": 1.2, "chain_damage_pct": 0.45, "biomass_on_kill": 3, "description": "Synergy capstone: apex predator chain kills."},
	# Chain 3: Hive Hunter → Nest Breaker → Queen Slayer
	{"id": "hive_hunter", "display_name": "Hive Hunter", "pool": "Swarm", "tags": ["hive", "hunter"], "tier": 1, "damage_mult": 1.1, "description": "+10% damage; hive focus."},
	{"id": "nest_breaker", "display_name": "Nest Breaker", "pool": "Swarm", "tags": ["hive", "breaker"], "tier": 2, "synergy_requires": ["hive"], "damage_mult": 1.2, "description": "Synergy: hunter → nest breaker."},
	{"id": "queen_slayer", "display_name": "Queen Slayer", "pool": "Swarm", "tags": ["hive", "slayer"], "tier": 3, "synergy_requires": ["breaker"], "damage_mult": 1.35, "fire_rate_mult": 1.08, "description": "Synergy capstone: anti-Overmind burst."},
	# Fillers
	{"id": "mobility_pack", "display_name": "Mobility Pack", "pool": "Mobility", "tags": ["mobility"], "tier": 1, "speed_mult": 1.12, "description": "+12% move speed."},
	{"id": "swarm_sweep", "display_name": "Swarm Sweep", "pool": "Swarm", "tags": ["swarm"], "tier": 1, "fire_rate_mult": 1.08, "description": "+8% fire rate vs swarms."},
]
