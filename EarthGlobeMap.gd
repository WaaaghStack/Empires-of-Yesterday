class_name EarthGlobeMap
extends Node3D

const BattleTileFluidFieldLib := preload("res://BattleTileFluidField.gd")
const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")
const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
const EarthGlobeMeshLib := preload("res://EarthGlobeMesh.gd")
const WorldConquestOutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
const WorldConquestResourcesLib := preload("res://WorldConquestResources.gd")

const ROAD_COLOR := Color(0.52, 0.52, 0.54)
const BRIDGE_COLOR := Color(0.62, 0.64, 0.68)
const ROAD_THICKNESS := 0.32
const BRIDGE_THICKNESS := 0.42
const ROAD_SURFACE_LIFT := 0.9

@onready var camera: Camera3D = $Camera3D

var battle_data = null
var _globe_mi: MeshInstance3D
var _fluid_mi: MeshInstance3D
var _markers: Node3D
var _effects: Node3D
var _roads: Node3D
var _deposits: Node3D
var _resource_links: Node3D
var _resource_pulses: Node3D
var _road_material: StandardMaterial3D
var _bridge_material: StandardMaterial3D
var _resource_link_material: StandardMaterial3D
var _resource_link_materials: Array[StandardMaterial3D] = []
var _resource_link_seg_count: Dictionary = {}
var _resource_link_nodes: Dictionary = {}
var _pulse_pool: Array[MeshInstance3D] = []
var _pulse_sphere_mesh: SphereMesh
var _pulse_materials: Array[StandardMaterial3D] = []
var _road_seg_count: Dictionary = {}
var _road_nodes: Dictionary = {}
var _path_cache: Dictionary = {} # sid -> PackedInt32Array
var _fluid_mat: StandardMaterial3D
var _fluid_tex: ImageTexture
var _land_mask: PackedByteArray = PackedByteArray()
var _cam_distance: float = WorldConquestConfigLib.CAMERA_DEFAULT_DISTANCE
var _yaw: float = -0.6
var _pitch: float = 0.35
var _dragging: bool = false
var _last_mouse: Vector2 = Vector2.ZERO


func setup(map_data) -> void:
	battle_data = map_data
	_land_mask = BattleTerritoryRustBackendLib.land_mask_from_map(map_data)
	if camera == null:
		camera = get_node_or_null("Camera3D") as Camera3D
	_build_scene()
	_frame_camera()


func _build_scene() -> void:
	for c in get_children():
		if c != camera:
			c.queue_free()
	_globe_mi = MeshInstance3D.new()
	_globe_mi.name = "Globe"
	_globe_mi.mesh = EarthGlobeMeshLib.build_globe(battle_data)
	var tmat := StandardMaterial3D.new()
	tmat.vertex_color_use_as_albedo = true
	tmat.roughness = 0.9
	tmat.cull_mode = BaseMaterial3D.CULL_BACK
	_globe_mi.material_override = tmat
	add_child(_globe_mi)
	_fluid_mi = MeshInstance3D.new()
	_fluid_mi.name = "Fluid"
	_fluid_mi.mesh = EarthGlobeMeshLib.build_fluid_globe(battle_data)
	_fluid_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fluid_mi.sorting_offset = 4.0
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	_fluid_tex = ImageTexture.create_from_image(Image.create(w, h, false, Image.FORMAT_RGBA8))
	_fluid_mat = StandardMaterial3D.new()
	_fluid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fluid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fluid_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fluid_mat.no_depth_test = true
	_fluid_mat.render_priority = 1
	_fluid_mat.albedo_texture = _fluid_tex
	_fluid_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_fluid_mi.material_override = _fluid_mat
	add_child(_fluid_mi)
	_markers = Node3D.new()
	_markers.name = "Markers"
	add_child(_markers)
	_effects = Node3D.new()
	_effects.name = "Effects"
	add_child(_effects)
	_roads = Node3D.new()
	_roads.name = "Roads"
	add_child(_roads)
	_deposits = Node3D.new()
	_deposits.name = "Deposits"
	add_child(_deposits)
	_resource_links = Node3D.new()
	_resource_links.name = "ResourceLinks"
	add_child(_resource_links)
	_resource_pulses = Node3D.new()
	_resource_pulses.name = "ResourcePulses"
	add_child(_resource_pulses)
	_road_material = StandardMaterial3D.new()
	_road_material.albedo_color = ROAD_COLOR
	_road_material.roughness = 0.95
	_road_material.metallic = 0.0
	_road_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bridge_material = StandardMaterial3D.new()
	_bridge_material.albedo_color = BRIDGE_COLOR
	_bridge_material.roughness = 0.85
	_bridge_material.metallic = 0.05
	_bridge_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_resource_link_material = StandardMaterial3D.new()
	_resource_link_material.albedo_color = Color(0.72, 0.68, 0.38, 0.85)
	_resource_link_material.emission_enabled = true
	_resource_link_material.emission = Color(0.55, 0.5, 0.2)
	_resource_link_material.emission_energy_multiplier = 0.6
	_resource_link_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_resource_link_materials.clear()
	for i in WorldConquestConfigLib.RESOURCE_TYPE_COUNT:
		var col: Color = WorldConquestConfigLib.RESOURCE_COLORS[i]
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color(col.r, col.g, col.b, 0.88)
		lmat.emission_enabled = true
		lmat.emission = col * 0.35
		lmat.emission_energy_multiplier = 0.6
		lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_resource_link_materials.append(lmat)
	_road_seg_count.clear()
	_road_nodes.clear()
	_path_cache.clear()
	_resource_link_seg_count.clear()
	_resource_link_nodes.clear()
	_pulse_pool.clear()
	_pulse_sphere_mesh = SphereMesh.new()
	_pulse_sphere_mesh.radius = 0.38
	_pulse_sphere_mesh.height = 0.76
	_pulse_materials.clear()
	for i in WorldConquestConfigLib.RESOURCE_TYPE_COUNT:
		var col: Color = WorldConquestConfigLib.RESOURCE_COLORS[i]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 2.4
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_pulse_materials.append(mat)
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		add_child(camera)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 50.0


func apply_fluid_from_pressures(
	pressure_friendly: PackedFloat32Array,
	pressure_hostile: PackedFloat32Array,
) -> void:
	if battle_data == null or _fluid_tex == null:
		return
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	var img: Image = null
	var rgba: PackedByteArray = BattleTerritoryRustBackendLib.bake_fluid_rgba(
		battle_data, pressure_friendly, pressure_hostile, 1.0, _land_mask
	)
	if not rgba.is_empty() and rgba.size() == w * h * 4:
		img = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, rgba)
	if img == null:
		img = BattleTileFluidFieldLib.build_fluid_image_from_powers(
			battle_data, pressure_friendly, pressure_hostile, 1.0, 0
		)
	if img == null:
		return
	_seal_texture_longitude_seam(img)
	_fluid_tex.update(img)


static func _seal_texture_longitude_seam(img: Image) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w < 2:
		return
	for gy in range(h):
		img.set_pixel(w - 1, gy, img.get_pixel(0, gy))


func refresh_resource_deposits(deposits: Array) -> void:
	if _deposits == null or battle_data == null:
		return
	for c in _deposits.get_children():
		c.queue_free()
	for dep: Dictionary in deposits:
		var type_i: int = int(dep.get("type", 0))
		var col: Color = WorldConquestConfigLib.RESOURCE_COLORS[
			clampi(type_i, 0, WorldConquestConfigLib.RESOURCE_TYPE_COUNT - 1)
		]
		var size_tier: int = int(dep.get("size", 1))
		var scale_f: float = 0.55 + float(size_tier) * 0.22
		_add_deposit_marker(
			Vector2i(int(dep.get("gx", 0)), int(dep.get("gy", 0))), col, scale_f
		)


func sync_resource_sites(site_states: Dictionary) -> void:
	if _resource_links == null or battle_data == null:
		return
	var live_ids: Dictionary = {}
	var w: int = battle_data.grid_width
	for site_key in site_states.keys():
		var state: Dictionary = site_states[site_key]
		var phase: String = str(state.get("phase", ""))
		if phase != WorldConquestResourcesLib.PHASE_LINKING and phase != WorldConquestResourcesLib.PHASE_HAULING:
			continue
		var link_path: PackedInt32Array = state.get("link_path", PackedInt32Array())
		if link_path.is_empty():
			continue
		var dep_id: int = _dep_id_from_site_key(str(site_key))
		if dep_id < 0:
			continue
		live_ids[dep_id] = true
		var built: int = link_path.size()
		if phase == WorldConquestResourcesLib.PHASE_LINKING:
			built = int(floor(float(state.get("link_built", 1.0))))
			built = clampi(built, 1, link_path.size())
		var type_i: int = int(state.get("type", 0))
		var need_segs: int = maxi(built - 1, 0)
		var have_segs: int = int(_resource_link_seg_count.get(dep_id, 0))
		if need_segs <= have_segs:
			continue
		for i in range(have_segs, need_segs):
			var a: Vector2i = WorldConquestOutpostBuildLib.grid_from_packed_key(link_path[i], w)
			var b: Vector2i = WorldConquestOutpostBuildLib.grid_from_packed_key(link_path[i + 1], w)
			_add_resource_link_segment(a, b, type_i, dep_id)
		_resource_link_seg_count[dep_id] = need_segs
	for dep_id in _resource_link_seg_count.keys():
		if not live_ids.has(dep_id):
			_clear_resource_link(dep_id)


func update_resource_pulses(pulses: Array) -> void:
	if _resource_pulses == null or battle_data == null:
		return
	_ensure_pulse_pool()
	if pulses.is_empty():
		for node: MeshInstance3D in _pulse_pool:
			node.visible = false
		return
	var show_n: int = mini(pulses.size(), _pulse_pool.size())
	for i in _pulse_pool.size():
		var node: MeshInstance3D = _pulse_pool[i]
		if i >= show_n:
			node.visible = false
			continue
		var pulse: Dictionary = pulses[i]
		var gx: int = int(pulse.get("gx", -1))
		var gy: int = int(pulse.get("gy", -1))
		if gx < 0:
			node.visible = false
			continue
		var type_i: int = clampi(int(pulse.get("type", 0)), 0, _pulse_materials.size() - 1)
		node.visible = true
		node.material_override = _pulse_materials[type_i]
		node.position = _grid_surface_pos(Vector2i(gx, gy), 1.1)


func refresh_markers(structures: Array, home_player: Vector2i, home_enemy: Vector2i) -> void:
	if _markers == null:
		return
	for c in _markers.get_children():
		c.queue_free()
	_add_capital_marker(home_player, Color(0.2, 0.55, 1.0), 2.2)
	_add_capital_marker(home_enemy, Color(0.95, 0.3, 0.22), 2.2)
	for st: Dictionary in structures:
		if str(st.get("kind", "")) != "spawner":
			continue
		var gx: int = int(st.get("gx", 0))
		var gy: int = int(st.get("gy", 0))
		var team: int = int(st.get("team", 1))
		var state: String = str(st.get("state", WorldConquestOutpostBuildLib.STATE_ACTIVE))
		var col: Color
		var scale_f: float = 1.0
		var alpha: float = 1.0
		var hp_frac: float = 1.0
		if st.has("health"):
			hp_frac = clampf(
				float(st.get("health", WorldConquestConfigLib.OUTPOST_MAX_HEALTH))
				/ WorldConquestConfigLib.OUTPOST_MAX_HEALTH,
				0.0,
				1.0,
			)
		match state:
			WorldConquestOutpostBuildLib.STATE_CONNECTING:
				col = Color(0.42, 0.44, 0.48)
				scale_f = 0.72
				alpha = 0.55
			WorldConquestOutpostBuildLib.STATE_BUILDING:
				var rem: float = float(
					st.get("build_remaining", WorldConquestConfigLib.OUTPOST_BUILD_SEC)
				)
				var prog: float = 1.0 - clampf(
					rem / WorldConquestConfigLib.OUTPOST_BUILD_SEC, 0.0, 1.0
				)
				col = Color(0.3, 0.45, 0.62).lerp(Color(0.25, 0.65, 1.0), prog)
				scale_f = lerpf(0.78, 1.0, prog)
				alpha = lerpf(0.65, 1.0, prog)
			_:
				col = Color(0.25, 0.65, 1.0) if team == 1 else Color(1.0, 0.4, 0.3)
		if state != WorldConquestOutpostBuildLib.STATE_ACTIVE and hp_frac < 1.0:
			col = col.lerp(Color(0.92, 0.28, 0.18), 1.0 - hp_frac)
			scale_f *= lerpf(0.85, 1.0, hp_frac)
		_add_capital_marker(Vector2i(gx, gy), col, scale_f, alpha)


func sync_roads(structures: Array) -> void:
	if _roads == null or battle_data == null:
		return
	var live_ids: Dictionary = {}
	for st: Dictionary in structures:
		if str(st.get("kind", "")) != "spawner":
			continue
		var sid: int = int(st.get("id", -1))
		if sid < 0:
			continue
		live_ids[sid] = true
		_sync_outpost_road(st, sid)
	for sid in _road_seg_count.keys():
		if not live_ids.has(sid):
			_clear_road(sid)


func _packed_path_keys(st: Dictionary, sid: int) -> PackedInt32Array:
	if _path_cache.has(sid):
		return _path_cache[sid]
	var packed: PackedInt32Array = st.get("path_keys", PackedInt32Array())
	if packed.is_empty():
		var w: int = battle_data.grid_width
		var legacy: Array[Vector2i] = WorldConquestOutpostBuildLib.path_from_structure(st, w)
		packed = WorldConquestOutpostBuildLib.path_to_packed_keys(legacy, w)
	_path_cache[sid] = packed
	return packed


func _sync_outpost_road(st: Dictionary, sid: int) -> void:
	var packed: PackedInt32Array = _packed_path_keys(st, sid)
	if packed.is_empty():
		return
	var w: int = battle_data.grid_width
	var state: String = str(st.get("state", WorldConquestOutpostBuildLib.STATE_ACTIVE))
	var built_cells: int
	if state == WorldConquestOutpostBuildLib.STATE_CONNECTING:
		built_cells = int(floor(float(st.get("path_built", 1.0))))
	else:
		built_cells = packed.size()
	built_cells = clampi(built_cells, 1, packed.size())
	var need_segs: int = maxi(built_cells - 1, 0)
	var have_segs: int = int(_road_seg_count.get(sid, 0))
	if need_segs <= have_segs:
		return
	for i in range(have_segs, need_segs):
		var a: Vector2i = WorldConquestOutpostBuildLib.grid_from_packed_key(packed[i], w)
		var b: Vector2i = WorldConquestOutpostBuildLib.grid_from_packed_key(packed[i + 1], w)
		_add_road_line_segment(a, b, sid)
	_road_seg_count[sid] = need_segs


func clear_road(sid: int) -> void:
	_clear_road(sid)


func spawn_outpost_destroy_fx(grid: Vector2i) -> void:
	if battle_data == null or grid.x < 0 or _effects == null:
		return
	var fx := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.4
	sphere.height = 2.8
	fx.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.12)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.35, 0.08)
	mat.emission_energy_multiplier = 2.2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fx.material_override = mat
	fx.position = _grid_surface_pos(grid, 2.0)
	_effects.add_child(fx)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(fx, "scale", Vector3(2.6, 2.6, 2.6), 0.45)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.45)
	tween.chain().tween_callback(fx.queue_free)


func _clear_road(sid: int) -> void:
	for seg in _road_nodes.get(sid, []):
		if is_instance_valid(seg):
			seg.queue_free()
	_road_nodes.erase(sid)
	_road_seg_count.erase(sid)
	_path_cache.erase(sid)


func _add_deposit_marker(grid: Vector2i, color: Color, scale_f: float) -> void:
	if battle_data == null or grid.x < 0 or _deposits == null:
		return
	var pos: Vector3 = _grid_surface_pos(grid, 0.55)
	var cyl := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.42 * scale_f
	mesh.bottom_radius = 0.52 * scale_f
	mesh.height = 0.35 * scale_f
	cyl.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.45
	mat.emission_energy_multiplier = 1.4
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyl.material_override = mat
	cyl.position = pos
	_deposits.add_child(cyl)


func _dep_id_from_site_key(site_key: String) -> int:
	if not site_key.begins_with("dep_"):
		return -1
	return int(site_key.substr(4))


func _clear_resource_link(dep_id: int) -> void:
	for seg in _resource_link_nodes.get(dep_id, []):
		if is_instance_valid(seg):
			seg.queue_free()
	_resource_link_nodes.erase(dep_id)
	_resource_link_seg_count.erase(dep_id)


func _ensure_pulse_pool() -> void:
	var want: int = WorldConquestConfigLib.RESOURCE_MAX_VISUAL_PULSES
	while _pulse_pool.size() < want:
		var pulse := MeshInstance3D.new()
		pulse.mesh = _pulse_sphere_mesh
		pulse.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pulse.visible = false
		_resource_pulses.add_child(pulse)
		_pulse_pool.append(pulse)


func _add_resource_link_segment(a: Vector2i, b: Vector2i, type_i: int, dep_id: int) -> void:
	if battle_data == null or a.x < 0 or b.x < 0:
		return
	var pos_a: Vector3 = _grid_surface_pos(a, 0.65)
	var pos_b: Vector3 = _grid_surface_pos(b, 0.65)
	var delta: Vector3 = pos_b - pos_a
	var length: float = delta.length()
	if length < 0.05:
		return
	var y_axis: Vector3 = delta / length
	var x_axis: Vector3 = y_axis.cross(Vector3.UP)
	if x_axis.length_squared() < 0.0001:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	var seg := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.18, length, 0.18)
	seg.mesh = bm
	var mat_i: int = clampi(type_i, 0, _resource_link_materials.size() - 1)
	seg.material_override = (
		_resource_link_materials[mat_i]
		if not _resource_link_materials.is_empty()
		else _resource_link_material
	)
	seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	seg.transform = Transform3D(Basis(x_axis, y_axis, z_axis), (pos_a + pos_b) * 0.5)
	_resource_links.add_child(seg)
	if not _resource_link_nodes.has(dep_id):
		_resource_link_nodes[dep_id] = []
	(_resource_link_nodes[dep_id] as Array).append(seg)


func _add_capital_marker(
	grid: Vector2i, color: Color, scale_f: float, alpha: float = 1.0
) -> void:
	if battle_data == null or grid.x < 0:
		return
	var pos: Vector3 = _grid_surface_pos(grid, 1.5)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8 * scale_f, 1.8 * scale_f, 1.8 * scale_f)
	box.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.emission_enabled = true
	mat.emission = color * 0.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 0.99 else BaseMaterial3D.TRANSPARENCY_DISABLED
	box.material_override = mat
	box.position = pos
	_markers.add_child(box)


func _add_road_line_segment(a: Vector2i, b: Vector2i, sid: int) -> void:
	if battle_data == null or a.x < 0 or b.x < 0:
		return
	var is_bridge: bool = _segment_is_bridge(a, b)
	var pos_a: Vector3 = _link_surface_pos(a)
	var pos_b: Vector3 = _link_surface_pos(b)
	var delta: Vector3 = pos_b - pos_a
	var length: float = delta.length()
	if length < 0.05:
		return
	var y_axis: Vector3 = delta / length
	var x_axis: Vector3 = y_axis.cross(Vector3.UP)
	if x_axis.length_squared() < 0.0001:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	var seg := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var thickness: float = BRIDGE_THICKNESS if is_bridge else ROAD_THICKNESS
	bm.size = Vector3(thickness, length, thickness)
	seg.mesh = bm
	seg.material_override = _bridge_material if is_bridge else _road_material
	seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	seg.transform = Transform3D(Basis(x_axis, y_axis, z_axis), (pos_a + pos_b) * 0.5)
	_roads.add_child(seg)
	if not _road_nodes.has(sid):
		_road_nodes[sid] = []
	(_road_nodes[sid] as Array).append(seg)


func _segment_is_bridge(a: Vector2i, b: Vector2i) -> bool:
	if battle_data == null:
		return false
	return (
		WorldConquestOutpostBuildLib.is_water_cell(battle_data, a.x, a.y)
		or WorldConquestOutpostBuildLib.is_water_cell(battle_data, b.x, b.y)
	)


func _link_surface_pos(grid: Vector2i) -> Vector3:
	if WorldConquestOutpostBuildLib.is_water_cell(battle_data, grid.x, grid.y):
		return _water_surface_pos(grid, WorldConquestConfigLib.BRIDGE_SURFACE_LIFT)
	return _grid_surface_pos(grid, ROAD_SURFACE_LIFT)


func _grid_surface_pos(grid: Vector2i, lift: float) -> Vector3:
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	var elev: float = battle_data.get_tile_height(grid.x, grid.y) * WorldConquestConfigLib.HEIGHT_SCALE
	return EarthGlobeMeshLib.grid_to_sphere(
		grid.x, grid.y, w, h, WorldConquestConfigLib.GLOBE_RADIUS + elev + lift, 0.0
	)


func _water_surface_pos(grid: Vector2i, lift: float) -> Vector3:
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	return EarthGlobeMeshLib.grid_to_sphere(
		grid.x, grid.y, w, h, WorldConquestConfigLib.GLOBE_RADIUS + lift, 0.0
	)


func orbit_camera(delta: float, mouse_delta: Vector2) -> void:
	if mouse_delta != Vector2.ZERO:
		_yaw -= mouse_delta.x * WorldConquestConfigLib.CAMERA_ORBIT_SPEED * 0.01
		_pitch = clampf(
			_pitch - mouse_delta.y * WorldConquestConfigLib.CAMERA_ORBIT_SPEED * 0.01,
			WorldConquestConfigLib.CAMERA_PITCH_MIN,
			WorldConquestConfigLib.CAMERA_PITCH_MAX,
		)
	_apply_camera()


func zoom_camera(zoom_in: bool) -> void:
	var step: float = WorldConquestConfigLib.CAMERA_ZOOM_STEP
	_cam_distance = _cam_distance / step if zoom_in else _cam_distance * step
	_cam_distance = clampf(
		_cam_distance,
		WorldConquestConfigLib.CAMERA_MIN_DISTANCE,
		WorldConquestConfigLib.CAMERA_MAX_DISTANCE,
	)
	_apply_camera()


func pick_grid_from_viewport(vp_pos: Vector2) -> Vector2i:
	if camera == null or battle_data == null:
		return Vector2i(-1, -1)
	var origin: Vector3 = camera.project_ray_origin(vp_pos)
	var dir: Vector3 = camera.project_ray_normal(vp_pos)
	var best_t: float = 1e9
	var best: Vector3 = Vector3.ZERO
	var r0: float = WorldConquestConfigLib.GLOBE_RADIUS
	var r1: float = r0 + WorldConquestConfigLib.HEIGHT_SCALE + 4.0
	for r in [r0, r1]:
		var a: float = dir.dot(dir)
		var b: float = 2.0 * origin.dot(dir)
		var c: float = origin.dot(origin) - r * r
		var disc: float = b * b - 4.0 * a * c
		if disc < 0.0:
			continue
		var t: float = (-b - sqrt(disc)) / (2.0 * a)
		if t > 0.0 and t < best_t:
			best_t = t
			best = origin + dir * t
	if best_t >= 1e8:
		return Vector2i(-1, -1)
	return EarthGlobeMeshLib.sphere_to_grid(
		best, battle_data.grid_width, battle_data.grid_height
	)


func _frame_camera() -> void:
	_yaw = -0.5
	_pitch = 0.4
	_cam_distance = WorldConquestConfigLib.CAMERA_DEFAULT_DISTANCE
	_apply_camera()


func _apply_camera() -> void:
	if camera == null:
		return
	var cp: float = cos(_pitch)
	var offset := Vector3(
		_cam_distance * cp * sin(_yaw),
		_cam_distance * sin(_pitch),
		_cam_distance * cp * cos(_yaw),
	)
	camera.position = offset
	camera.look_at(Vector3.ZERO, Vector3.UP)
