# Enemy.gd
class_name Enemy
extends Resource

enum Archetype { RIFLEMAN, HEAVY, SNIPER }

@export var enemy_name: String = "Enemy"
@export var health: int = 50
@export var damage: int = 15
@export var speed: float = 100.0
@export var attack_range: float = 110.0
@export var fire_rate: float = 0.7
@export var aggro_range: float = 420.0
@export var leash_range: float = 260.0
@export var archetype: Archetype = Archetype.RIFLEMAN
@export var alive: bool = true

static func create_archetype(type: Archetype, scale: float, enemy_id: int) -> Enemy:
	var res := Enemy.new()
	res.enemy_name = "H-%d" % enemy_id
	res.archetype = type
	match type:
		Archetype.RIFLEMAN:
			res.health = int(45 * scale) + enemy_id * 2
			res.damage = int(10 * scale) + 1
			res.speed = 80.0
			res.attack_range = 110.0
			res.fire_rate = 0.7
		Archetype.HEAVY:
			res.health = int(90 * scale) + enemy_id * 3
			res.damage = int(14 * scale) + 2
			res.speed = 50.0
			res.attack_range = 85.0
			res.fire_rate = 0.5
			res.aggro_range = 320.0
		Archetype.SNIPER:
			res.health = int(30 * scale) + enemy_id
			res.damage = int(18 * scale) + 2
			res.speed = 40.0
			res.attack_range = 220.0
			res.fire_rate = 0.55
			res.aggro_range = 500.0
			res.leash_range = 180.0
	res.alive = true
	return res

static func make_archetype(type: Archetype, enemy_id: int, scale: float = 1.0) -> Enemy:
	return create_archetype(type, scale, enemy_id)

static func archetype_label(type: Archetype) -> String:
	match type:
		Archetype.HEAVY:
			return "Heavy"
		Archetype.SNIPER:
			return "Sniper"
		_:
			return "Rifleman"

static func pick_archetype_for_op(op_index: int, rng: RandomNumberGenerator, is_elite: bool = false) -> Archetype:
	if is_elite:
		return Archetype.HEAVY if rng.randf() > 0.5 else Archetype.SNIPER
	match op_index:
		1:
			return Archetype.RIFLEMAN
		2:
			return Archetype.RIFLEMAN if rng.randf() > 0.35 else Archetype.HEAVY
		3:
			var roll := rng.randf()
			if roll < 0.4:
				return Archetype.HEAVY
			if roll < 0.7:
				return Archetype.SNIPER
			return Archetype.RIFLEMAN
		_:
			var roll2 := rng.randf()
			if roll2 < 0.35:
				return Archetype.HEAVY
			if roll2 < 0.65:
				return Archetype.SNIPER
			return Archetype.RIFLEMAN
