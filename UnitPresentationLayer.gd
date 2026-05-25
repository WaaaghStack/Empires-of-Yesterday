class_name UnitPresentationLayer
extends Node2D

const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")

const LITE_MESH_COLOR_FRIENDLY := Color(0.35, 0.75, 1.0, 0.9)
const LITE_MESH_COLOR_HOSTILE := Color(0.95, 0.35, 0.3, 0.9)

var _store: UnitSimulationStoreLib
var _friendly_mesh: MultiMeshInstance2D
var _hostile_mesh: MultiMeshInstance2D
var _friendly_instance_by_index: Dictionary = {}
var _hostile_instance_by_index: Dictionary = {}
var _update_frame_skip: int = 0


func setup(store: UnitSimulationStoreLib, parent_world: Node2D) -> void:
	_store = store
	z_index = 8
	if get_parent() != parent_world:
		parent_world.add_child(self)
	_friendly_mesh = _make_mesh_instance("FriendlyLite", LITE_MESH_COLOR_FRIENDLY)
	_hostile_mesh = _make_mesh_instance("HostileLite", LITE_MESH_COLOR_HOSTILE)
	add_child(_friendly_mesh)
	add_child(_hostile_mesh)


func reset() -> void:
	_friendly_instance_by_index.clear()
	_hostile_instance_by_index.clear()
	if _friendly_mesh and _friendly_mesh.multimesh:
		_friendly_mesh.multimesh.instance_count = 0
	if _hostile_mesh and _hostile_mesh.multimesh:
		_hostile_mesh.multimesh.instance_count = 0


func refresh_instances() -> void:
	if _store == null:
		return
	_friendly_instance_by_index.clear()
	_hostile_instance_by_index.clear()
	var friendly_count := 0
	var hostile_count := 0
	for i in range(_store.count):
		if not _store.is_alive(i):
			continue
		if _store.tier[i] != UnitSimulationStoreLib.Tier.LITE:
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
		if _store.tier[i] != UnitSimulationStoreLib.Tier.LITE:
			continue
		var xform := Transform2D(0.0, _store.positions[i])
		xform = xform.scaled(Vector2(0.35, 0.35))
		if _store.side[i] == UnitSimulationStoreLib.Side.FRIENDLY:
			_friendly_mesh.multimesh.set_instance_transform_2d(fi, xform)
			_friendly_instance_by_index[i] = fi
			fi += 1
		else:
			_hostile_mesh.multimesh.set_instance_transform_2d(hi, xform)
			_hostile_instance_by_index[i] = hi
			hi += 1


func update_transforms() -> void:
	if _store == null:
		return
	_update_frame_skip += 1
	if _store.count > 2000 and _update_frame_skip % 2 != 0:
		return
	for store_idx in _friendly_instance_by_index.keys():
		var inst: int = _friendly_instance_by_index[store_idx]
		if store_idx < _store.count and _store.is_alive(store_idx):
			var xform := Transform2D(0.0, _store.positions[store_idx])
			_friendly_mesh.multimesh.set_instance_transform_2d(inst, xform.scaled(Vector2(0.35, 0.35)))
	for store_idx in _hostile_instance_by_index.keys():
		var inst_h: int = _hostile_instance_by_index[store_idx]
		if store_idx < _store.count and _store.is_alive(store_idx):
			var xform_h := Transform2D(0.0, _store.positions[store_idx])
			_hostile_mesh.multimesh.set_instance_transform_2d(inst_h, xform_h.scaled(Vector2(0.35, 0.35)))


func _make_mesh_instance(node_name: String, color: Color) -> MultiMeshInstance2D:
	var mm := MultiMeshInstance2D.new()
	mm.name = node_name
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_2D
	multi.use_colors = false
	var quad := QuadMesh.new()
	quad.size = Vector2(12, 12)
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
