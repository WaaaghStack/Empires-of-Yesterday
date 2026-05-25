class_name CommanderProfile
extends RefCounted

const PROFILES: Array[Dictionary] = [
	{
		"id": "logistician",
		"name": "Logistician",
		"description": "Strong economy and recruitment. Weaker frontline damage.",
		"starting_soldiers": 1200,
		"starting_manpower": 80,
		"starting_biomass": 40,
		"starting_alloys": 20,
		"damage_mult": 0.92,
		"defense_mult": 1.0,
		"economy_mult": 1.25,
		"ability_id": "supply_drop",
		"ability_name": "Supply Drop",
	},
	{
		"id": "hammer",
		"name": "Hammer",
		"description": "Assault specialist. Extra damage, thinner logistics.",
		"starting_soldiers": 1000,
		"starting_manpower": 60,
		"starting_biomass": 30,
		"starting_alloys": 30,
		"damage_mult": 1.18,
		"defense_mult": 0.95,
		"economy_mult": 0.9,
		"ability_id": "orbital_strike",
		"ability_name": "Orbital Strike",
	},
	{
		"id": "bulwark",
		"name": "Bulwark",
		"description": "Defensive commander. Fewer losses, slower conquest.",
		"starting_soldiers": 1100,
		"starting_manpower": 70,
		"starting_biomass": 35,
		"starting_alloys": 25,
		"damage_mult": 0.95,
		"defense_mult": 1.2,
		"economy_mult": 1.0,
		"ability_id": "fortify_line",
		"ability_name": "Fortify Line",
	},
]


static func get_by_id(commander_id: String) -> Dictionary:
	for profile in PROFILES:
		if str(profile.get("id", "")) == commander_id:
			return profile.duplicate(true)
	return PROFILES[0].duplicate(true)


static func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for profile in PROFILES:
		ids.append(str(profile.get("id", "")))
	return ids
