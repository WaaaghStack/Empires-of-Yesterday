class_name LoadoutPreset
extends Resource

@export var id: String = "assault_std"
@export var display_name: String = "Standard Assault"
@export var archetype: String = "assault"
@export var weapon_tag: String = "kinetic"
@export var damage_mult: float = 1.0
@export var fire_rate_mult: float = 1.0
@export var health_mult: float = 1.0
@export var speed_mult: float = 1.0
@export var defense_bonus: int = 0
@export var description: String = ""


static func get_catalog() -> Array[LoadoutPreset]:
	var presets: Array[LoadoutPreset] = []
	for spec in _PRESET_SPECS:
		var p: LoadoutPreset = load("res://LoadoutPreset.gd").new()
		p.id = spec.get("id", "")
		p.display_name = spec.get("display_name", p.id)
		p.archetype = spec.get("archetype", "assault")
		p.weapon_tag = spec.get("weapon_tag", "kinetic")
		p.damage_mult = float(spec.get("damage_mult", 1.0))
		p.fire_rate_mult = float(spec.get("fire_rate_mult", 1.0))
		p.health_mult = float(spec.get("health_mult", 1.0))
		p.speed_mult = float(spec.get("speed_mult", 1.0))
		p.defense_bonus = int(spec.get("defense_bonus", 0))
		p.description = str(spec.get("description", ""))
		presets.append(p)
	return presets


static func get_by_id(preset_id: String) -> LoadoutPreset:
	for preset in get_catalog():
		if preset.id == preset_id:
			return preset
	return null


static func presets_for_archetype(role_archetype: String) -> Array[LoadoutPreset]:
	var result: Array[LoadoutPreset] = []
	for preset in get_catalog():
		if preset.archetype == role_archetype:
			result.append(preset)
	return result


static func apply_to_resource(resource: SoldierResource, preset: LoadoutPreset) -> void:
	if not resource or not preset:
		return
	resource.loadout_preset_id = preset.id
	resource.weapon_tag = preset.weapon_tag
	resource.damage = maxi(1, int(resource.damage * preset.damage_mult))
	resource.fire_rate = maxf(0.1, resource.fire_rate * preset.fire_rate_mult)
	resource.health = maxi(1, int(resource.health * preset.health_mult))
	resource.speed = maxf(10.0, resource.speed * preset.speed_mult)
	resource.defense = maxi(0, resource.defense + preset.defense_bonus)


const _PRESET_SPECS: Array[Dictionary] = [
	{"id": "assault_std", "display_name": "Line Rifle", "archetype": "assault", "weapon_tag": "kinetic", "description": "Balanced kinetic rifle loadout."},
	{"id": "assault_plasma", "display_name": "Plasma Assault", "archetype": "assault", "weapon_tag": "energy", "damage_mult": 1.12, "fire_rate_mult": 0.92, "description": "Energy-heavy assault kit."},
	{"id": "assault_shock", "display_name": "Shock Trooper", "archetype": "assault", "weapon_tag": "kinetic", "damage_mult": 1.08, "speed_mult": 1.08, "description": "Fast close-range breach kit."},
	{"id": "support_std", "display_name": "Field Medic", "archetype": "support", "weapon_tag": "kinetic", "health_mult": 1.05, "description": "Standard support loadout."},
	{"id": "support_bio", "display_name": "Bio-Support", "archetype": "support", "weapon_tag": "bio", "health_mult": 1.12, "defense_bonus": 1, "description": "Bio-resistant field kit."},
	{"id": "support_pulse", "display_name": "Pulse Carbine", "archetype": "support", "weapon_tag": "energy", "fire_rate_mult": 1.1, "description": "Suppression energy carbine."},
	{"id": "marksman_std", "display_name": "Longbow", "archetype": "marksman", "weapon_tag": "kinetic", "damage_mult": 1.15, "fire_rate_mult": 0.85, "description": "Precision kinetic rifle."},
	{"id": "marksman_laser", "display_name": "Beam Lance", "archetype": "marksman", "weapon_tag": "energy", "damage_mult": 1.2, "fire_rate_mult": 0.8, "description": "High-energy sniper beam."},
	{"id": "breacher_std", "display_name": "Breacher", "archetype": "breacher", "weapon_tag": "kinetic", "damage_mult": 1.1, "defense_bonus": 2, "description": "Door-kicker shotgun loadout."},
	{"id": "breacher_flame", "display_name": "Incendiary", "archetype": "breacher", "weapon_tag": "fire", "damage_mult": 1.05, "fire_rate_mult": 1.05, "description": "Fire-tag breaching kit."},
]
