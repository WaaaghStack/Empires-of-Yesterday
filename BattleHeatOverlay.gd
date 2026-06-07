class_name BattleHeatOverlay
extends Node2D

const BattleMapDataLib := preload("res://BattleMapData.gd")
const BattleTacticalSimLib := preload("res://BattleTacticalSim.gd")

var _battle_data = null
var _tactical: BattleTacticalSimLib = null
var _pulse: float = 0.0


func setup(battle_data, tactical: BattleTacticalSimLib = null) -> void:
	_battle_data = battle_data
	_tactical = tactical
	z_index = -3


func set_tactical_sim(tactical: BattleTacticalSimLib) -> void:
	_tactical = tactical


func sync_capture_pulse(_cp_id: String) -> void:
	queue_redraw()


func tick(delta: float) -> void:
	_pulse += delta
	queue_redraw()


func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	if _battle_data == null or _tactical == null or _tactical.store == null:
		return
	var cell_size: float = _battle_data.cell_size
	for gy in range(_battle_data.grid_height):
		for gx in range(_battle_data.grid_width):
			if not _tactical.cell_grid.has_both_sides_at(gx, gy, _tactical.store):
				continue
			var center: Vector2 = _battle_data.cell_center(gx, gy)
			var n: int = _tactical.cell_grid.units_at(gx, gy).size()
			var heat: float = clampf(float(n) / 20.0, 0.15, 0.85)
			var col := Color(0.95, 0.35, 0.15, heat * 0.35)
			draw_circle(center, cell_size * 0.42, col)
