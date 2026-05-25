class_name CommanderResources
extends RefCounted

var manpower: int = 0
var biomass: int = 0
var alloys: int = 0


func reset_from_profile(profile: Dictionary) -> void:
	manpower = int(profile.get("starting_manpower", 50))
	biomass = int(profile.get("starting_biomass", 30))
	alloys = int(profile.get("starting_alloys", 20))


func to_dict() -> Dictionary:
	return {"manpower": manpower, "biomass": biomass, "alloys": alloys}


func from_dict(data: Dictionary) -> void:
	manpower = int(data.get("manpower", 0))
	biomass = int(data.get("biomass", 0))
	alloys = int(data.get("alloys", 0))
