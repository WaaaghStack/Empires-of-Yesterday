class_name BattleHeatOverlay
extends Node2D

const BattleMapDataLib := preload("res://BattleMapData.gd")
const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")

var _battle_data = null
var _store: UnitSimulationStoreLib = null
var _flip_flash_timer: float = 0.0
var _flip_flash_center := Vector2.ZERO
var _flip_flash_color := Color.WHITE
var _last_flip_id: String = ""


func setup(battle_data, store: UnitSimulationStoreLib) -> void:
	_battle_data = battle_data
	_store = store
	z_index = -3


func sync_flip(flip_region_id: String) -> void:
	if flip_region_id.is_empty() or flip_region_id == _last_flip_id:
		return
	_last_flip_id = flip_region_id
	if _battle_data == null:
		return
	var region: Dictionary = _battle_data.get_region(flip_region_id)
	if region.is_empty():
		return
	_flip_flash_center = region.get("center", Vector2.ZERO)
	var control := str(region.get("control", BattleMapDataLib.CONTROL_NEUTRAL))
	if control == BattleMapDataLib.CONTROL_PLAYER:
		_flip_flash_color = Color(0.35, 0.75, 1.0, 0.85)
	elif control == BattleMapDataLib.CONTROL_ENEMY:
		_flip_flash_color = Color(0.95, 0.35, 0.3, 0.85)
	else:
		_flip_flash_color = Color(0.7, 0.72, 0.78, 0.7)
	_flip_flash_timer = 0.65
	queue_redraw()


func tick(delta: float) -> void:
	if _flip_flash_timer > 0.0:
		_flip_flash_timer = maxf(0.0, _flip_flash_timer - delta)
		queue_redraw()


func refresh() -> void:
	queue_redraw()


func unit_count_for_region(region: Dictionary) -> int:
	if _store == null:
		return 0
	var region_id := str(region.get("id", ""))
	var room_idx := _store.room_index_for_id(region_id)
	if room_idx < 0:
		return 0
	var friendlies := 0
	var hostiles := 0
	if room_idx < _store.friendly_count_by_room.size():
		friendlies = _store.friendly_count_by_room[room_idx]
	if room_idx < _store.hostile_count_by_room.size():
		hostiles = _store.hostile_count_by_room[room_idx]
	return friendlies + hostiles


func heat_radius_for_region(region: Dictionary) -> float:
	var units := unit_count_for_region(region)
	if units <= 0:
		return 0.0
	return clampf(8.0 + sqrt(float(units)) * 4.0, 12.0, 80.0)


func _draw() -> void:
	if _battle_data == null:
		return
	_draw_contact_band()
	if _store != null:
		_draw_army_heat()
	_draw_objective_rings()
	_draw_flip_flash()


func _draw_contact_band() -> void:
	var half: Vector2 = _battle_data.map_size * 0.5
	var contact_x: float = (float(_battle_data.contact_column) + 0.5) * _battle_data.cell_size - half.x
	var band_w: float = _battle_data.cell_size * 4.2
	var top := -half.y
	var height: float = _battle_data.map_size.y
	var steps := 12
	for i in range(steps):
		var t0: float = float(i) / float(steps)
		var t1: float = float(i + 1) / float(steps)
		var x0: float = contact_x - band_w * 0.5 + band_w * t0
		var x1: float = contact_x - band_w * 0.5 + band_w * t1
		var center_t: float = absf((t0 + t1) * 0.5 - 0.5) * 2.0
		var alpha: float = lerpf(0.06, 0.32, 1.0 - center_t)
		draw_rect(
			Rect2(x0, top, x1 - x0, height),
			Color(0.55, 0.62, 0.72, alpha),
		)


func _draw_army_heat() -> void:
	for region in _battle_data.regions:
		var units := unit_count_for_region(region)
		if units <= 0:
			continue
		var center: Vector2 = region.get("center", Vector2.ZERO)
		var radius := heat_radius_for_region(region)
		var control := str(region.get("control", BattleMapDataLib.CONTROL_NEUTRAL))
		var base := _control_color(control)
		base.a = 0.38
		draw_circle(center, radius, base)
		var inner := base
		inner.a = 0.55
		draw_circle(center, radius * 0.45, inner)


func _draw_objective_rings() -> void:
	for region in _battle_data.regions:
		if not bool(region.get("is_objective", false)):
			continue
		var center: Vector2 = region.get("center", Vector2.ZERO)
		var rect: Rect2 = _battle_data.region_world_rect(region)
		var ring_r: float = minf(rect.size.x, rect.size.y) * 0.22
		draw_arc(center, ring_r, 0.0, TAU, 48, Color(1.0, 0.92, 0.25, 0.75), 3.0, true)


func _draw_flip_flash() -> void:
	if _flip_flash_timer <= 0.0:
		return
	var t: float = 1.0 - (_flip_flash_timer / 0.65)
	var radius: float = lerpf(18.0, 120.0, t)
	var alpha: float = lerpf(0.7, 0.0, t)
	var col := _flip_flash_color
	col.a = alpha
	draw_arc(_flip_flash_center, radius, 0.0, TAU, 64, col, 4.0, true)


func _control_color(control: String) -> Color:
	match control:
		BattleMapDataLib.CONTROL_PLAYER:
			return Color(0.2, 0.55, 0.95, 1.0)
		BattleMapDataLib.CONTROL_ENEMY:
			return Color(0.9, 0.25, 0.2, 1.0)
		_:
			return Color(0.45, 0.48, 0.52, 1.0)
