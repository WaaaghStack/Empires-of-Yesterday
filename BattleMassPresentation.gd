class_name BattleMassPresentation
extends Node2D

const UnitSimulationStoreLib := preload("res://UnitSimulationStore.gd")
const CombatFxLib := preload("res://CombatFx.gd")
const BattleMusouFeelLib := preload("res://BattleMusouFeel.gd")
const BattleUnitCatalogLib := preload("res://BattleUnitCatalog.gd")

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
var _bucket_frame: int = 0
var _pending_deaths: Array = []
var _replay_visual_mode: bool = false


func setup(store: UnitSimulationStoreLib, parent_world: Node2D, impostor_size: float = 22.0) -> void:
	_store = store
	_impostor_size = impostor_size
	z_index = 8
	if get_parent() == null:
		parent_world.add_child(self)
	elif get_parent() != parent_world:
		get_parent().remove_child(self)
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


## When true, SIM_ONLY units are drawn (smaller) so replays show the full battle.
func set_replay_visual_mode(enabled: bool) -> void:
	_replay_visual_mode = enabled


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
		if _store.tier[i] == UnitSimulationStoreLib.Tier.SIM_ONLY and not _replay_visual_mode:
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
		if _store.tier[i] == UnitSimulationStoreLib.Tier.SIM_ONLY and not _replay_visual_mode:
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


func update_transforms(delta: float = 0.0, dirty_indices: PackedInt32Array = PackedInt32Array()) -> void:
	if _store == null:
		return
	_impact_budget += MAX_IMPACTS_PER_SEC * delta
	_update_frame_skip += 1
	_bucket_frame = (_bucket_frame + 1) % UnitSimulationStoreLib.SIM_BUCKETS
	_process_pending_deaths()
	var use_dirty: bool = dirty_indices.size() > 0
	var use_buckets: bool = _store.count > 1500 and not use_dirty
	if use_dirty:
		for i in range(dirty_indices.size()):
			_update_instance_transform(int(dirty_indices[i]))
	elif use_buckets:
		for store_idx in _friendly_instance_by_index.keys():
			var idx_f: int = int(store_idx)
			if idx_f % UnitSimulationStoreLib.SIM_BUCKETS != _bucket_frame:
				continue
			_update_instance_transform(idx_f)
		for store_idx in _hostile_instance_by_index.keys():
			var idx_h: int = int(store_idx)
			if idx_h % UnitSimulationStoreLib.SIM_BUCKETS != _bucket_frame:
				continue
			_update_instance_transform(idx_h)
	else:
		for store_idx in _friendly_instance_by_index.keys():
			_update_instance_transform(int(store_idx))
		for store_idx in _hostile_instance_by_index.keys():
			_update_instance_transform(int(store_idx))


func notify_deaths(dead_indices: Array) -> void:
	for d in dead_indices:
		_pending_deaths.append(int(d))
	_process_pending_deaths()
	# Rebuild meshes so dead units vanish (no stale transforms left on screen).
	if not dead_indices.is_empty():
		refresh_instances()


func notify_dirty_from_store() -> void:
	if _store == null:
		return
	update_transforms(0.0, _store.collect_dirty_transform_indices())


func update_all_visible_transforms() -> void:
	if _store == null:
		return
	for store_idx in _friendly_instance_by_index.keys():
		_update_instance_transform(int(store_idx))
	for store_idx in _hostile_instance_by_index.keys():
		_update_instance_transform(int(store_idx))
	_process_pending_deaths()


func _update_instance_transform(store_idx: int) -> void:
	if not _should_draw_unit(store_idx):
		_hide_instance(store_idx)
		return
	var scale := _scale_for_index(store_idx)
	var xform := Transform2D(0.0, _store.positions[store_idx]).scaled(Vector2(scale, scale))
	if _friendly_instance_by_index.has(store_idx):
		var inst: int = _friendly_instance_by_index[store_idx]
		_friendly_mesh.multimesh.set_instance_transform_2d(inst, xform)
	elif _hostile_instance_by_index.has(store_idx):
		var inst_h: int = _hostile_instance_by_index[store_idx]
		_hostile_mesh.multimesh.set_instance_transform_2d(inst_h, xform)


func _process_pending_deaths() -> void:
	if _store == null or _pending_deaths.is_empty():
		return
	_resize_alive_flags()
	for i in _pending_deaths:
		var idx: int = int(i)
		if idx < 0 or idx >= _store.count:
			continue
		if _friendly_instance_by_index.has(idx) or _hostile_instance_by_index.has(idx):
			if idx < _was_alive.size() and _was_alive[idx] == 1:
				_spawn_death_impact(idx)
		if idx < _was_alive.size():
			_was_alive[idx] = 0
	_pending_deaths.clear()


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


func _hide_instance(store_idx: int) -> void:
	var hidden := Transform2D(0.0, Vector2(-1e6, -1e6)).scaled(Vector2.ZERO)
	if _friendly_instance_by_index.has(store_idx):
		var inst: int = _friendly_instance_by_index[store_idx]
		_friendly_mesh.multimesh.set_instance_transform_2d(inst, hidden)
	elif _hostile_instance_by_index.has(store_idx):
		var inst_h: int = _hostile_instance_by_index[store_idx]
		_hostile_mesh.multimesh.set_instance_transform_2d(inst_h, hidden)


func _should_draw_unit(store_idx: int) -> bool:
	if _store == null or store_idx < 0 or store_idx >= _store.count:
		return false
	if not _store.is_alive(store_idx):
		return false
	if _store.tier[store_idx] == UnitSimulationStoreLib.Tier.DORMANT:
		return false
	if _store.tier[store_idx] == UnitSimulationStoreLib.Tier.SIM_ONLY and not _replay_visual_mode:
		return false
	return true


func _scale_for_index(store_idx: int) -> float:
	var scale := _base_scale
	if _store == null or store_idx < 0 or store_idx >= _store.count:
		return scale
	if _replay_visual_mode and _store.tier[store_idx] == UnitSimulationStoreLib.Tier.SIM_ONLY:
		scale *= 0.55
	var pos: Vector2 = _store.positions[store_idx]
	var dist_contact: float = BattleMusouFeelLib.contact_dist_x(pos.x, _contact_x, _store.side[store_idx])
	scale += BattleMusouFeelLib.contact_scale_boost(
		dist_contact, _contact_cell_size, _musou_elapsed, _store.ids[store_idx]
	)
	var dist := pos.distance_to(_camera_pos)
	var promote_r := PROMOTE_RADIUS_BASE / _camera_zoom
	if dist <= promote_r:
		scale *= LOD_NEAR_MULT
	var def = BattleUnitCatalogLib.get_by_archetype(_store.archetype[store_idx])
	scale *= def.impostor_scale
	return clampf(scale, 0.85, 1.55)


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
