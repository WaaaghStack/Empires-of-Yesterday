class_name SoldierResource
extends Resource

const OrderTypeLib := preload("res://OrderType.gd")

enum MarineClass { ASSAULT, SUPPORT, MARKSMAN, BREACHER }

@export var soldier_name: String = "Rookie"
@export var marine_class: MarineClass = MarineClass.ASSAULT
@export var health: int = 100
@export var defense: int = 6
@export var damage: int = 25
@export var speed: float = 120.0
@export var attack_range: float = 140.0
@export var fire_rate: float = 1.0
@export var portrait: Texture2D
@export var description: String = "Standard Rifleman"
@export_multiline var bio: String = ""
@export var ability_name: String = "Adrenaline"
@export var ability_cooldown: float = 12.0
@export var default_order: OrderTypeLib.Type = OrderTypeLib.Type.CLEAR
@export var current_hp: int = -1
@export var is_kia: bool = false
@export var is_injured: bool = false
@export var squad_id: String = "alpha"
@export var trait_id: String = ""
@export var loadout_preset_id: String = ""
@export var weapon_tag: String = "kinetic"
@export var stress: float = 0.0

const INJURY_SPEED_PENALTY := 0.10
const INJURY_FIRE_RATE_PENALTY := 0.15
const INJURY_ABILITY_CD_MULT := 1.25

const OPERATOR_RESOURCES: Array[String] = [
	"res://Soldier_Marine1.tres",
	"res://Soldier_Marine2.tres",
	"res://Soldier_Marine3.tres",
	"res://Soldier_Marine4.tres",
]

static func apply_class_flavor(resource: SoldierResource) -> void:
	match resource.marine_class:
		MarineClass.ASSAULT:
			resource.ability_name = "Adrenaline"
			if resource.default_order == OrderTypeLib.Type.NONE:
				resource.default_order = OrderTypeLib.Type.CLEAR
		MarineClass.SUPPORT:
			resource.ability_name = "Field Repair"
			if resource.default_order == OrderTypeLib.Type.NONE:
				resource.default_order = OrderTypeLib.Type.DEFEND
		MarineClass.MARKSMAN:
			resource.ability_name = "Focus Fire"
			if resource.default_order == OrderTypeLib.Type.NONE:
				resource.default_order = OrderTypeLib.Type.CLEAR
		MarineClass.BREACHER:
			resource.ability_name = "Breaching Charge"
			if resource.default_order == OrderTypeLib.Type.NONE:
				resource.default_order = OrderTypeLib.Type.SEARCH_DESTROY

static func apply_class_defaults(resource: SoldierResource) -> void:
	apply_class_flavor(resource)
	match resource.marine_class:
		MarineClass.ASSAULT:
			resource.health = 120
			resource.defense = 8
			resource.damage = 28
			resource.speed = 58.0
			resource.attack_range = 130.0
			resource.fire_rate = 1.1
			resource.description = "Frontline fighter. Adrenaline rush pushes the assigned sector."
		MarineClass.SUPPORT:
			resource.health = 100
			resource.defense = 6
			resource.damage = 16
			resource.speed = 52.0
			resource.attack_range = 120.0
			resource.fire_rate = 0.9
			resource.description = "Field medic. Field Repair aura heals allies holding a defend sector."
		MarineClass.MARKSMAN:
			resource.health = 85
			resource.defense = 4
			resource.damage = 38
			resource.speed = 55.0
			resource.attack_range = 190.0
			resource.fire_rate = 0.75
			resource.description = "Overwatch specialist. Focus Fire marks priority targets for the squad."
		MarineClass.BREACHER:
			resource.health = 130
			resource.defense = 12
			resource.damage = 32
			resource.speed = 59.0
			resource.attack_range = 95.0
			resource.fire_rate = 1.2
			resource.description = "Breacher. Breaching Charge blows bulkheads and clears chokepoints."

func get_stats_line() -> String:
	return "HP %d · DEF %d · SPD %.0f · DMG %d" % [health, defense, speed, damage]

func get_deploy_hp() -> int:
	if is_kia:
		return 0
	if current_hp < 0:
		return health
	return clampi(current_hp, 0, health)

func get_effective_speed() -> float:
	var penalty: float = INJURY_SPEED_PENALTY if is_injured else 0.0
	return speed * (1.0 - penalty)

func get_effective_fire_rate() -> float:
	var penalty: float = INJURY_FIRE_RATE_PENALTY if is_injured else 0.0
	return fire_rate * (1.0 - penalty)

func get_effective_ability_cooldown() -> float:
	return ability_cooldown * (INJURY_ABILITY_CD_MULT if is_injured else 1.0)

static func get_roster_operators() -> Array[SoldierResource]:
	var roster: Array[SoldierResource] = []
	for path in OPERATOR_RESOURCES:
		if not ResourceLoader.exists(path):
			continue
		var res: SoldierResource = load(path)
		if res:
			apply_class_flavor(res)
			roster.append(res)
	return roster

func get_bio_line() -> String:
	if not bio.is_empty():
		return bio
	return description

func reset_for_new_run() -> void:
	current_hp = -1
	is_kia = false
	is_injured = false
	stress = 0.0


static func apply_trait_passive(resource: SoldierResource) -> void:
	match resource.trait_id:
		"Steady":
			resource.fire_rate = maxf(0.1, resource.fire_rate * 1.05)
		"Reckless":
			resource.damage = int(resource.damage * 1.1)
			resource.defense = maxi(0, resource.defense - 1)
		"Hive-Hater":
			resource.damage = int(resource.damage * 1.08)
		"Veteran":
			resource.health = int(resource.health * 1.06)
		"Ghost":
			resource.speed = resource.speed * 1.06


func get_stress_accuracy_penalty() -> float:
	return clampf(stress * 0.08, 0.0, 0.35)


func add_stress(amount: float) -> void:
	stress = clampf(stress + amount, 0.0, 1.0)


func duplicate_for_deploy() -> SoldierResource:
	var copy: SoldierResource = duplicate(true) as SoldierResource
	copy.portrait = portrait
	copy.current_hp = current_hp
	copy.is_kia = is_kia
	copy.is_injured = is_injured
	copy.squad_id = squad_id
	copy.trait_id = trait_id
	copy.loadout_preset_id = loadout_preset_id
	copy.weapon_tag = weapon_tag
	copy.stress = stress
	apply_class_flavor(copy)
	return copy
