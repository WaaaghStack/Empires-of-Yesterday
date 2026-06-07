class_name BattleMagicBudget
extends RefCounted

const CommanderProfileLib := preload("res://CommanderProfile.gd")

static func gems_for_profile(profile: Dictionary = {}) -> int:
	var base := 10
	var econ: float = float(profile.get("economy_mult", 1.0))
	return int(roundf(float(base) * econ)) + 4


static func attach_to_commanders(commanders: Array, profile: Dictionary = {}) -> void:
	var total: int = gems_for_profile(profile)
	var friendly_cmds: Array = []
	for cmd in commanders:
		if cmd.side == 0:
			friendly_cmds.append(cmd)
	if friendly_cmds.is_empty():
		return
	var per: int = maxi(1, total / friendly_cmds.size())
	for cmd in friendly_cmds:
		cmd.gems_remaining = per
