class_name BattleUnitAnalysis
extends RefCounted

const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")
const BattleUnitCatalogLib := preload("res://BattleUnitCatalog.gd")

const MAX_LIST_ROWS := 48


static func build_report(store: UnitSimulationStoreLib, final_round: int = 0) -> Dictionary:
	if store == null or store.count <= 0:
		return _empty_report()
	var rows: Array = []
	var friendly_kills: int = 0
	var hostile_kills: int = 0
	var friendly_dead: int = 0
	var hostile_dead: int = 0
	for i in range(store.count):
		var k: int = store.kills[i] if i < store.kills.size() else 0
		var died: bool = not store.is_alive(i)
		var side: int = store.side[i]
		if side == UnitSimulationStoreLib.Side.FRIENDLY:
			friendly_kills += k
			if died:
				friendly_dead += 1
		else:
			hostile_kills += k
			if died:
				hostile_dead += 1
		if k <= 0 and not died:
			continue
		var def = BattleUnitCatalogLib.get_by_archetype(store.archetype[i])
		var death_r: int = int(store.death_round[i]) if i < store.death_round.size() else -1
		rows.append({
			"unit_index": i,
			"unit_id": store.ids[i] if i < store.ids.size() else i,
			"side": side,
			"side_name": "Blue" if side == UnitSimulationStoreLib.Side.FRIENDLY else "Red",
			"archetype": store.archetype[i],
			"type_name": def.display_name if def else "Unit",
			"kills": k,
			"died": died,
			"death_round": death_r,
			"squad_index": store.squad_index[i] if i < store.squad_index.size() else 0,
		})
	rows.sort_custom(func(a, b):
		if int(a["kills"]) != int(b["kills"]):
			return int(a["kills"]) > int(b["kills"])
		return bool(a["died"]) and not bool(b["died"])
	)
	if rows.size() > MAX_LIST_ROWS:
		rows = rows.slice(0, MAX_LIST_ROWS)
	return {
		"final_round": final_round,
		"friendly_kills": friendly_kills,
		"hostile_kills": hostile_kills,
		"friendly_dead": friendly_dead,
		"hostile_dead": hostile_dead,
		"friendly_spawned": store.living_friendly_count() + friendly_dead,
		"hostile_spawned": store.living_hostile_count() + hostile_dead,
		"units": rows,
	}


static func format_summary_text(
	player_won: bool,
	analysis: Dictionary,
	player_losses: int,
	enemy_losses: int,
	terrain: String,
) -> String:
	var outcome := "VICTORY" if player_won else "DEFEAT"
	var fk: int = int(analysis.get("friendly_kills", 0))
	var hk: int = int(analysis.get("hostile_kills", 0))
	var fd: int = int(analysis.get("friendly_dead", 0))
	var hd: int = int(analysis.get("hostile_dead", 0))
	var rnd: int = int(analysis.get("final_round", 0))
	return (
		"%s — %s\n\nBlue kills: %d  |  Red kills: %d\nBlue fallen: %d  |  Red fallen: %d\n"
		+ "Allocation losses — Blue: %d  Red: %d\nRounds fought: %d"
		% [outcome, terrain.capitalize(), fk, hk, fd, hd, player_losses, enemy_losses, rnd]
	)


static func format_unit_lines(analysis: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var units: Array = analysis.get("units", [])
	if units.is_empty():
		lines.append("No per-unit combat highlights recorded.")
		return lines
	lines.append("Side    Type         Kills  Status")
	lines.append("----------------------------------------")
	for row in units:
		var status := "ALIVE"
		if bool(row.get("died", false)):
			var dr: int = int(row.get("death_round", -1))
			status = "KIA r%d" % dr if dr >= 0 else "KIA"
		lines.append(
			"%-6s  %-11s  %5d  %s"
			% [
				str(row.get("side_name", "?")),
				str(row.get("type_name", "Unit")).substr(0, 11),
				int(row.get("kills", 0)),
				status,
			]
		)
	return lines


static func _empty_report() -> Dictionary:
	return {
		"final_round": 0,
		"friendly_kills": 0,
		"hostile_kills": 0,
		"friendly_dead": 0,
		"hostile_dead": 0,
		"friendly_spawned": 0,
		"hostile_spawned": 0,
		"units": [],
	}
