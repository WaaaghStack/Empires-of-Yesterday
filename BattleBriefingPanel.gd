class_name BattleBriefingPanel
extends RefCounted

const BattleOrderTypesLib := preload("res://BattleOrderTypes.gd")
const BattleEnemyDoctrineLib := preload("res://BattleEnemyDoctrine.gd")
const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")


static func format_briefing_text(battle_data, player_count: int, enemy_count: int, squad_count: int) -> String:
	var terrain: String = str(battle_data.terrain_tag if battle_data else "field").capitalize().replace("_", " ")
	var body := (
		"%s Battle\n\n%d soldiers vs %d defenders in %d squads.\n\n"
		+ "Assign squad scripts and commander magic queue, then engage.\n"
		+ "Victory: rout the enemy army or annihilate all hostiles.\n\nClick to begin."
	)
	return body % [terrain, player_count, enemy_count, squad_count]


static func apply_player_defaults(script, squads: Array, commanders: Array) -> void:
	for squad in squads:
		if squad.side == UnitSimulationStoreLib.Side.FRIENDLY:
			script.set_squad_order(squad.id, BattleOrderTypesLib.SquadOrder.ATTACK_CLOSEST)
	for cmd in commanders:
		if cmd.side == UnitSimulationStoreLib.Side.FRIENDLY:
			script.set_commander_queue(
				cmd.id,
				[
					BattleOrderTypesLib.CommanderStep.BLESS_SQUAD,
					BattleOrderTypesLib.CommanderStep.CAST_SPELL,
					BattleOrderTypesLib.CommanderStep.WAIT,
					BattleOrderTypesLib.CommanderStep.CAST_SPELL,
					BattleOrderTypesLib.CommanderStep.WAIT,
				],
			)
	script.apply_to_squads(squads)
	script.apply_to_commanders(commanders)
	BattleEnemyDoctrineLib.apply_default_scripts(script, squads, commanders)
