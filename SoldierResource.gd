class_name SoldierResource
extends Resource

enum MarineClass { ASSAULT, SUPPORT, MARKSMAN, BREACHER }

@export var soldier_name: String = "Rookie"
@export var marine_class: MarineClass = MarineClass.ASSAULT
@export var health: int = 100
@export var damage: int = 25
@export var speed: float = 120.0
@export var attack_range: float = 140.0
@export var fire_rate: float = 1.0
@export var portrait: Texture2D
@export var description: String = "Standard Rifleman"
@export var ability_name: String = "Adrenaline"
@export var ability_cooldown: float = 12.0

static func apply_class_defaults(resource: SoldierResource) -> void:
	match resource.marine_class:
		MarineClass.ASSAULT:
			resource.health = 120
			resource.damage = 28
			resource.speed = 115.0
			resource.attack_range = 130.0
			resource.fire_rate = 1.1
			resource.ability_name = "Adrenaline"
			resource.description = "Frontline fighter. Balanced stats and burst damage."
		MarineClass.SUPPORT:
			resource.health = 100
			resource.damage = 16
			resource.speed = 105.0
			resource.attack_range = 120.0
			resource.fire_rate = 0.9
			resource.ability_name = "Field Repair"
			resource.description = "Keeps the squad alive with emergency healing."
		MarineClass.MARKSMAN:
			resource.health = 85
			resource.damage = 38
			resource.speed = 110.0
			resource.attack_range = 190.0
			resource.fire_rate = 0.75
			resource.ability_name = "Focus Fire"
			resource.description = "Long-range specialist with high single-target damage."
		MarineClass.BREACHER:
			resource.health = 130
			resource.damage = 32
			resource.speed = 125.0
			resource.attack_range = 95.0
			resource.fire_rate = 1.2
			resource.ability_name = "Breaching Charge"
			resource.description = "Close-range room clearer. Faster objective completion."

func duplicate_for_deploy() -> SoldierResource:
	var copy: SoldierResource = duplicate(true) as SoldierResource
	apply_class_defaults(copy)
	return copy
