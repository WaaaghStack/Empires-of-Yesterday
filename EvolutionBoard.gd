class_name EvolutionBoard
extends RefCounted

const EvolutionUpgradeLib := preload("res://EvolutionUpgrade.gd")

var squad_id: String = "alpha"
var applied_ids: Array[String] = []
var applied_tags: Array[String] = []
var max_upgrades: int = 12


func reset(p_squad_id: String = "alpha") -> void:
	squad_id = p_squad_id
	applied_ids.clear()
	applied_tags.clear()


func has_upgrade(upgrade_id: String) -> bool:
	return upgrade_id in applied_ids


func has_tag(tag: String) -> bool:
	return tag in applied_tags


func can_apply(upgrade) -> bool:
	if upgrade == null:
		return false
	if has_upgrade(upgrade.id):
		return false
	if applied_ids.size() >= max_upgrades:
		return false
	for req in upgrade.synergy_requires:
		if not has_tag(req):
			return false
	return true


func apply_upgrade(upgrade, units: Array = []) -> bool:
	if not can_apply(upgrade):
		return false
	applied_ids.append(upgrade.id)
	for tag in upgrade.tags:
		if tag not in applied_tags:
			applied_tags.append(tag)
	for unit in units:
		if unit is SoldierUnit:
			_apply_to_unit(unit as SoldierUnit, upgrade)
	return true


func _apply_to_unit(unit: SoldierUnit, upgrade) -> void:
	if upgrade.squad_wide and unit.squad_id != squad_id:
		return
	if not upgrade.squad_wide and unit.squad_id != squad_id:
		return
	unit.apply_evolution_upgrade(upgrade)


func get_tier_reached() -> int:
	var max_tier := 0
	for upgrade_id in applied_ids:
		var upgrade := EvolutionUpgradeLib.get_by_id(upgrade_id)
		if upgrade:
			max_tier = maxi(max_tier, upgrade.tier)
	return max_tier


func get_summary_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for upgrade_id in applied_ids:
		var upgrade := EvolutionUpgradeLib.get_by_id(upgrade_id)
		if upgrade:
			lines.append(upgrade.display_name)
	return lines
