class_name BattleMassPresentation
extends Node2D

const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")
const CombatFxLib := preload("res://CombatFx.gd")
const BattleMusouFeelLib := preload("res://BattleMusouFeel.gd")

const LITE_MESH_COLOR_FRIENDLY := Color(0.35, 0.75, 1.0, 0.92)
const LITE_MESH_COLOR_HOSTILE := Color(0.95, 0.35, 0.3, 0.92)
const LOD_NEAR_MULT := 1.4
const PROMOTE_RADIUS_BASE := 960.0
const MAX_IMPACTS_PER_SEC := 40.0

var _store: UnitSimulationStoreLib
var _impostor_size: float = 22.0
var _base_scale: float = 0.92
var _camera_pos := Vector2.ZERO
var _camera_zoom: float = 0.45
var _friendly_mesh: MultiMeshInstance2D
var _hostile_mesh: MultiMeshInstance2D
var _friendly_instance_by_index: Dictionary = {}
var _hostile_instance_by_index: Dictionary = {}
var _update_frame_skip: int = 0
var _was_alive: PackedByteArray = PackedByteArray()
var _impact_budget: float = 0.0
var _contact_x: float = 0.0
var _contact_cell_size: float = 32.0
var _musou_elapsed: float = 0.0


func setup(store: UnitSimulationStoreLib, parent_world: Node2D, impostor_size: float = 22.0) -> void:
	_store = store
	_impostor_size = impostor_size
	z_index = 8
	if get_parent() != parent_world:
		parent_world.add_child(self)
	_friendly_mesh = _make_mesh_instance("FriendlyMass", LITE_MESH_COLOR_FRIENDLY)
	_hostile_mesh = _make_mesh_instance("HostileMass", LITE_MESH_COLOR_HOSTILE)
	add_child(_friendly_mesh)
	add_child(_hostile_mesh)


func set_camera(camera_pos: Vector2, zoom: float) -> void:
	_camera_pos = camera_pos
	_camera_zoom = maxf(zoom, 0.15)


func set_contact_line(contact_x: float, cell_size: float) -> void:
	_contact_x = contact_x
	_contact_cell_size = cell_size


func set_musou_time(elapsed: float) -> void:
	_musou_elapsed = elapsed


func reset() -> void:
	_friendly_instance_by_index.clear()
	_hostile_instance_by_index.clear()
	_was_alive = PackedByteArray()
	if _friendly_mesh and _friendly_mesh.multimesh:
		_friendly_mesh.multimesh.instance_count = 0
	if _hostile_mesh and _hostile_mesh.multimesh:
		_hostile_mesh.multimesh.instance_count = 0


func refresh_instances() -> void:
	if _store == null:
		return
	_friendly_instance_by_index.clear()
	_hostile_instance_by_index.clear()
	_resize_alive_flags()
	var friendly_count := 0
	var hostile_count := 0
	for i in range(_store.count):
		if not _store.is_alive(i):
			continue
		if _store.tier[i] == UnitSimulationStoreLib.Tier.DORMANT:
			continue
		if _store.tier[i] == UnitSimulationStoreLib.Tier.SIM_ONLY:
			continue
		if _store.side[i] == UnitSimulationStoreLib.Side.FRIENDLY:
			friendly_count += 1
		else:
			hostile_count += 1
	_ensure_mesh_capacity(_friendly_mesh, friendly_count)
	_ensure_mesh_capacity(_hostile_mesh, hostile_count)
	var fi := 0
	var hi := 0
	for i in range(_store.count):
		if not _store.is_alive(i):
			continue
		if _store.tier[i] == UnitSimulationStoreLib.Tier.DORMANT:
			continue
		if _store.tier[i] == UnitSimulationStoreLib.Tier.SIM_ONLY:
			continue
		var scale := _scale_for_index(i)
		var xform := Transform2D(0.0, _store.positions[i]).scaled(Vector2(scale, scale))
		if _store.side[i] == UnitSimulationStoreLib.Side.FRIENDLY:
			_friendly_mesh.multimesh.set_instance_transform_2d(fi, xform)
			_friendly_instance_by_index[i] = fi
			fi += 1
		else:
			_hostile_mesh.multimesh.set_instance_transform_2d(hi, xform)
			_hostile_instance_by_index[i] = hi
			hi += 1


func update_transforms(delta: float = 0.0) -> void:
	if _store == null:
		return
	_impact_budget += MAX_IMPACTS_PER_SEC * delta
	_update_frame_skip += 1
	if _store.count > 2000 and _update_frame_skip % 2 != 0:
		_process_deaths_only()
		return
	for store_idx in _friendly_instance_by_index.keys():
		var inst: int = _friendly_instance_by_index[store_idx]
		if store_idx < _store.count and _store.is_alive(store_idx):
			var scale := _scale_for_index(store_idx)
			var xform := Transform2D(0.0, _store.positions[store_idx]).scaled(Vector2(scale, scale))
			_friendly_mesh.multimesh.set_instance_transform_2d(inst, xform)
	for store_idx in _hostile_instance_by_index.keys():
		var inst_h: int = _hostile_instance_by_index[store_idx]
		if store_idx < _store.count and _store.is_alive(store_idx):
			var scale_h := _scale_for_index(store_idx)
			var xform_h := Transform2D(0.0, _store.positions[store_idx]).scaled(Vector2(scale_h, scale_h))
			_hostile_mesh.multimesh.set_instance_transform_2d(inst_h, xform_h)
	_process_deaths_only()


func _process_deaths_only() -> void:
	if _store == null:
		return
	_resize_alive_flags()
	for i in range(_store.count):
		var alive: int = 1 if _store.is_alive(i) else 0
		if i < _was_alive.size() and _was_alive[i] == 1 and alive == 0:
			_spawn_death_impact(i)
		if i < _was_alive.size():
			_was_alive[i] = alive


func _spawn_death_impact(store_idx: int) -> void:
	if _impact_budget < 1.0:
		return
	_impact_budget -= 1.0
	var pos: Vector2 = _store.positions[store_idx] if store_idx < _store.positions.size() else Vector2.ZERO
	var marker := Node2D.new()
	marker.position = pos
	add_child(marker)
	var col := LITE_MESH_COLOR_FRIENDLY if _store.side[store_idx] == UnitSimulationStoreLib.Side.FRIENDLY else LITE_MESH_COLOR_HOSTILE
	CombatFxLib.spawn_impact(marker, col)
	marker.queue_free()


func _scale_for_index(store_idx: int) -> float:
	var scale := _base_scale
	if _store == null or store_idx < 0 or store_idx >= _store.count:
		return scale
	var pos: Vector2 = _store.positions[store_idx]
	var dist_contact: float = BattleMusouFeelLib.contact_dist_x(pos.x, _contact_x, _store.side[store_idx])
	scale += BattleMusouFeelLib.contact_scale_boost(
		dist_contact, _contact_cell_size, _musou_elapsed, _store.ids[store_idx]
	)
	var dist := pos.distance_to(_camera_pos)
	var promote_r := PROMOTE_RADIUS_BASE / _camera_zoom
	if dist <= promote_r:
		scale *= LOD_NEAR_MULT
	return clampf(scale, 0.85, 1.48)


func _make_mesh_instance(node_name: String, color: Color) -> MultiMeshInstance2D:
	var mm := MultiMeshInstance2D.new()
	mm.name = node_name
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_2D
	multi.use_colors = false
	var quad := QuadMesh.new()
	quad.size = Vector2(_impostor_size, _impostor_size)
	multi.mesh = quad
	multi.instance_count = 0
	mm.multimesh = multi
	mm.modulate = color
	return mm


func _ensure_mesh_capacity(mesh_inst: MultiMeshInstance2D, needed: int) -> void:
	if mesh_inst == null or mesh_inst.multimesh == null:
		return
	if mesh_inst.multimesh.instance_count != needed:
		mesh_inst.multimesh.instance_count = needed


func _resize_alive_flags() -> void:
	if _store == null:
		return
	if _was_alive.size() == _store.count:
		return
	_was_alive.resize(_store.count)
	for i in range(_store.count):
		_was_alive[i] = 1 if _store.is_alive(i) else 0
