# Enemy.gd
class_name Enemy
extends Resource

enum Kind { RIFLEMAN, HEAVY, SNIPER, FLANKER }

@export var enemy_name: String = "Enemy"
@export var health: int = 50
@export var damage: int = 15
@export var speed: float = 100.0
@export var attack_range: float = 110.0
@export var fire_rate: float = 0.7
@export var aggro_range: float = 420.0
@export var leash_range: float = 260.0
@export var archetype: Kind = Kind.RIFLEMAN

static func create_archetype(type: Kind, scale: float, enemy_id: int) -> Enemy:
	var res := Enemy.new()
	res.enemy_name = "H-%d" % enemy_id
	res.archetype = type
	match type:
		Kind.RIFLEMAN:
			res.health = int(45 * scale) + enemy_id * 2
			res.damage = int(10 * scale) + 1
			res.speed = 80.0
			res.attack_range = 110.0
			res.fire_rate = 0.7
		Kind.HEAVY:
			res.health = int(90 * scale) + enemy_id * 3
			res.damage = int(14 * scale) + 2
			res.speed = 50.0
			res.attack_range = 85.0
			res.fire_rate = 0.5
			res.aggro_range = 320.0
		Kind.SNIPER:
			res.health = int(30 * scale) + enemy_id
			res.damage = int(18 * scale) + 2
			res.speed = 40.0
			res.attack_range = 220.0
			res.fire_rate = 0.55
			res.aggro_range = 500.0
			res.leash_range = 180.0
		Kind.FLANKER:
			res.health = int(28 * scale) + enemy_id
			res.damage = int(11 * scale) + 1
			res.speed = 118.0
			res.attack_range = 75.0
			res.fire_rate = 0.85
			res.aggro_range = 380.0
			res.leash_range = 320.0
	return res

static func make_archetype(type: Kind, enemy_id: int, scale: float = 1.0) -> Enemy:
	return create_archetype(type, scale, enemy_id)

static func archetype_label(type: Kind) -> String:
	match type:
		Kind.HEAVY:
			return "Heavy"
		Kind.SNIPER:
			return "Sniper"
		Kind.FLANKER:
			return "Flanker"
		_:
			return "Rifleman"

static func pick_archetype_for_op(op_index: int, rng: RandomNumberGenerator, is_elite: bool = false) -> Kind:
	if is_elite:
		return Kind.HEAVY if rng.randf() > 0.5 else Kind.SNIPER
	match op_index:
		1:
			return Kind.RIFLEMAN
		2:
			return Kind.RIFLEMAN if rng.randf() > 0.35 else Kind.HEAVY
		3:
			var roll := rng.randf()
			if roll < 0.3:
				return Kind.HEAVY
			if roll < 0.5:
				return Kind.SNIPER
			if roll < 0.72:
				return Kind.FLANKER
			return Kind.RIFLEMAN
		_:
			var roll2 := rng.randf()
			if roll2 < 0.28:
				return Kind.HEAVY
			if roll2 < 0.5:
				return Kind.SNIPER
			if roll2 < 0.72:
				return Kind.FLANKER
			return Kind.RIFLEMAN
