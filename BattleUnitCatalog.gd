class_name BattleUnitCatalog
extends RefCounted

const BattleUnitDefinitionLib := preload("res://BattleUnitDefinition.gd")

const ARCH_INFANTRY := 0
const ARCH_ARCHER := 1
const ARCH_CAVALRY := 2
const ARCH_COMMANDER := 3

static var _defs: Array = []
static var _ready := false


static func ensure_loaded() -> void:
	if _ready:
		return
	_ready = true
	var infantry := BattleUnitDefinitionLib.new("infantry", "Infantry", 10.0, 12.0, 2, 1.0, ARCH_INFANTRY)
	infantry.apply_dom_stats(1, 12, 10, 8, 10, 10, 0, 10, false, false, 0)
	var archer := BattleUnitDefinitionLib.new("archer", "Archer", 8.0, 8.0, 2, 0.92, ARCH_ARCHER)
	archer.apply_dom_stats(1, 8, 8, 14, 9, 10, 0, 10, false, true, 5)
	var cavalry := BattleUnitDefinitionLib.new("cavalry", "Cavalry", 14.0, 9.0, 3, 1.08, ARCH_CAVALRY)
	cavalry.apply_dom_stats(2, 11, 14, 8, 11, 14, 2, 10, false, false, 0)
	cavalry.tags = ["charge"]
	var commander := BattleUnitDefinitionLib.new("commander", "Commander", 16.0, 14.0, 2, 1.2, ARCH_COMMANDER)
	commander.apply_dom_stats(3, 14, 12, 10, 15, 12, 0, 14, true, false, 0)
	_defs = [infantry, archer, cavalry, commander]


static func get_by_archetype(archetype_index: int) -> BattleUnitDefinitionLib:
	ensure_loaded()
	var idx: int = clampi(archetype_index, 0, _defs.size() - 1)
	return _defs[idx]


static func get_by_id(unit_id: String) -> BattleUnitDefinitionLib:
	ensure_loaded()
	for d in _defs:
		if d.id == unit_id:
			return d
	return _defs[0]
