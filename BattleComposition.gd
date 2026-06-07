class_name BattleComposition
extends RefCounted

const BattleUnitCatalogLib := preload("res://BattleUnitCatalog.gd")


static func build_archetype_list(count: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	var out := PackedInt32Array()
	if count <= 0:
		return out
	out.resize(count)
	for i in range(count):
		var roll: float = rng.randf()
		if roll < 0.6:
			out[i] = BattleUnitCatalogLib.ARCH_INFANTRY
		elif roll < 0.85:
			out[i] = BattleUnitCatalogLib.ARCH_ARCHER
		else:
			out[i] = BattleUnitCatalogLib.ARCH_CAVALRY
	return out


static func cohort_id_for_unit(unit_index: int, cohort_count: int) -> int:
	if cohort_count <= 0:
		return 0
	return unit_index % cohort_count
