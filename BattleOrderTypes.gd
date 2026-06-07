class_name BattleOrderTypes
extends RefCounted

enum SquadOrder {
	ATTACK_CLOSEST,
	HOLD_AND_ATTACK_REAR,
	HOLD_POSITION,
	ADVANCE_CONTACT,
}

enum CommanderStep {
	CAST_SPELL,
	WAIT,
	ATTACK_CLOSEST,
	BLESS_SQUAD,
}

const COMMANDER_QUEUE_LEN := 5
