class_name BattleUnitDefinition
extends RefCounted

var id: String = "infantry"
var display_name: String = "Infantry"
var tags: Array = []
var hp: float = 100.0
var attack: float = 10.0
var defense: float = 10.0
var move_cells_per_turn: int = 2
var impostor_scale: float = 1.0
var archetype_index: int = 0
var skills: Array = []
## Dominions-style tactical stats
var size: int = 1
var protection: int = 0
var strength: int = 10
var precision: int = 10
var morale: int = 15
var combat_speed: int = 10
var encumbrance: int = 0
var mr: int = 10
var is_commander: bool = false
var ranged: bool = false
var range_cells: int = 0


func _init(
	unit_id: String = "infantry",
	name: String = "Infantry",
	unit_attack: float = 10.0,
	unit_defense: float = 10.0,
	move_cells: int = 2,
	scale: float = 1.0,
	arch_index: int = 0,
) -> void:
	id = unit_id
	display_name = name
	attack = unit_attack
	defense = unit_defense
	move_cells_per_turn = move_cells
	impostor_scale = scale
	archetype_index = arch_index


func apply_dom_stats(
	unit_size: int,
	prot: int,
	str: int,
	prec: int,
	mor: int,
	speed: int,
	enc: int,
	magic_res: int,
	commander: bool,
	is_ranged: bool,
	rng_cells: int,
) -> void:
	size = unit_size
	protection = prot
	strength = str
	precision = prec
	morale = mor
	combat_speed = speed
	encumbrance = enc
	mr = magic_res
	is_commander = commander
	ranged = is_ranged
	range_cells = rng_cells
