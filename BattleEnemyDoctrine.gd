class_name BattleEnemyDoctrine
extends RefCounted

const BattleOrderTypesLib := preload("res://BattleOrderTypes.gd")
const BattleScriptLib := preload("res://BattleScript.gd")
const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")

const DOCTRINE_AGGRESSIVE := "aggressive"
const DOCTRINE_DEFENSIVE := "defensive"


static func apply_default_scripts(script: BattleScriptLib, squads: Array, commanders: Array, doctrine: String = DOCTRINE_AGGRESSIVE) -> void:
	var squad_order: int = (
		BattleOrderTypesLib.SquadOrder.ATTACK_CLOSEST
		if doctrine == DOCTRINE_AGGRESSIVE
		else BattleOrderTypesLib.SquadOrder.HOLD_AND_ATTACK_REAR
	)
	for squad in squads:
		if squad.side != UnitSimulationStoreLib.Side.HOSTILE:
			continue
		script.set_squad_order(squad.id, squad_order)
	for cmd in commanders:
		if cmd.side != UnitSimulationStoreLib.Side.HOSTILE:
			continue
		script.set_commander_queue(
			cmd.id,
			[
				BattleOrderTypesLib.CommanderStep.CAST_SPELL,
				BattleOrderTypesLib.CommanderStep.ATTACK_CLOSEST,
				BattleOrderTypesLib.CommanderStep.WAIT,
				BattleOrderTypesLib.CommanderStep.CAST_SPELL,
				BattleOrderTypesLib.CommanderStep.WAIT,
			],
		)
	script.apply_to_squads(squads)
	script.apply_to_commanders(commanders)
