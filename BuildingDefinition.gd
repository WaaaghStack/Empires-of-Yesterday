class_name BuildingDefinition
extends RefCounted

const DEFINITIONS: Dictionary = {
	"barracks": {
		"id": "barracks",
		"name": "Barracks",
		"cost_biomass": 25,
		"cost_alloys": 10,
		"manpower_per_turn": 5,
		"recruit_per_turn": 40,
	},
	"forge": {
		"id": "forge",
		"name": "Forge",
		"cost_biomass": 20,
		"cost_alloys": 25,
		"alloys_per_turn": 8,
		"damage_bonus": 0.05,
	},
	"sensor_array": {
		"id": "sensor_array",
		"name": "Sensor Array",
		"cost_biomass": 30,
		"cost_alloys": 15,
		"biomass_per_turn": 10,
		"intel_bonus": 1,
	},
	"field_hospital": {
		"id": "field_hospital",
		"name": "Field Hospital",
		"cost_biomass": 35,
		"cost_alloys": 5,
		"casualty_reduction": 0.08,
	},
}


static func lookup(building_id: String) -> Dictionary:
	if DEFINITIONS.has(building_id):
		return DEFINITIONS[building_id].duplicate(true)
	return {}


static func all_buildable_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in DEFINITIONS.keys():
		ids.append(str(key))
	return ids
