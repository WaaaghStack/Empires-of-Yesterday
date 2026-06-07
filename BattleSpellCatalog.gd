class_name BattleSpellCatalog
extends RefCounted

const SPELL_FIREBALL := "fireball"
const SPELL_BLESS := "bless"
const SPELL_FEAR := "fear"
const SPELL_SLEEP := "sleep"

static var _spells: Dictionary = {}


static func ensure_loaded() -> void:
	if not _spells.is_empty():
		return
	_spells = {
		SPELL_FIREBALL: {"gems": 3, "path": "fire", "aoe": 1, "damage": 18},
		SPELL_BLESS: {"gems": 2, "path": "nature", "morale_bonus": 3, "damage_bonus": 2},
		SPELL_FEAR: {"gems": 2, "path": "death", "morale_penalty": 4},
		SPELL_SLEEP: {"gems": 4, "path": "astral", "fatigue_add": 40.0},
	}


static func get_spell(spell_id: String) -> Dictionary:
	ensure_loaded()
	return _spells.get(spell_id, {}).duplicate()


static func default_spell_for_step(step: int) -> String:
	match step % 4:
		0:
			return SPELL_FIREBALL
		1:
			return SPELL_BLESS
		2:
			return SPELL_FEAR
		_:
			return SPELL_SLEEP
