class_name RunAugment
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""


static func overwatch_drone() -> RunAugment:
	var aug := new()
	aug.id = "overwatch_drone"
	aug.display_name = "Overwatch Drone"
	aug.description = "+1 adjacent sector revealed at deploy."
	return aug


static func docs_kit() -> RunAugment:
	var aug := new()
	aug.id = "docs_kit"
	aug.display_name = "Doc's Kit"
	aug.description = "+10% squad heal efficiency in the hub."
	return aug


static func field_intel() -> RunAugment:
	var aug := new()
	aug.id = "field_intel"
	aug.display_name = "Field Intel Uplink"
	aug.description = "-5 run credits on all intel shop purchases."
	return aug


static func spare_parts() -> RunAugment:
	var aug := new()
	aug.id = "spare_parts"
	aug.display_name = "Spare Parts Crate"
	aug.description = "+5 run credits after each cleared operation."
	return aug


static func all_augments() -> Array[RunAugment]:
	return [overwatch_drone(), docs_kit(), field_intel(), spare_parts()]


static func pick_random_two(_rng: RandomNumberGenerator) -> Array[RunAugment]:
	var pool: Array[RunAugment] = all_augments()
	pool.shuffle()
	var result: Array[RunAugment] = []
	for i in range(mini(2, pool.size())):
		result.append(pool[i])
	return result
