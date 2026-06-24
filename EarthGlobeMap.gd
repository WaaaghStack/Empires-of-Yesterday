class_name EarthGlobeMap
extends Node3D

const BattleTileFluidFieldLib := preload("res://BattleTileFluidField.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")
const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
const EarthGlobeMeshLib := preload("res://EarthGlobeMesh.gd")
const WorldConquestOutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
const WorldConquestResourcesLib := preload("res://WorldConquestResources.gd")

const ROAD_COLOR := Color(0.52, 0.52, 0.54)
const BRIDGE_COLOR := Color(0.62, 0.64, 0.68)
const ROAD_THICKNESS := 0.32
const BRIDGE_THICKNESS := 0.42
const ROAD_SURFACE_LIFT := 2.75
const ROAD_RENDER_PRIORITY := 8

@onready var camera: Camera3D = $Camera3D

var battle_data = null
var _globe_mi: MeshInstance3D
var _fluid_mi: MeshInstance3D
var _markers: Node3D
var _soldiers: Node3D
var _builders: Node3D
var _effects: Node3D
var _roads: Node3D
var _deposits: Node3D
var _resource_links: Node3D
var _resource_pulses: Node3D
var _road_material: StandardMaterial3D
var _bridge_material: StandardMaterial3D
var _resource_link_material: StandardMaterial3D
var _resource_link_materials: Array[StandardMaterial3D] = []
var _resource_link_materials_linking: Array[StandardMaterial3D] = []
var _resource_link_seg_count: Dictionary = {}
var _resource_link_nodes: Dictionary = {}
var _pulse_pool: Array[MeshInstance3D] = []
var _pulse_sphere_mesh: SphereMesh
var _pulse_materials: Array[StandardMaterial3D] = []
var _marker_pool: Array[MeshInstance3D] = []
var _marker_pool_used: int = 0
var _soldier_pool: Array[MeshInstance3D] = []
var _soldier_pool_used: int = 0
var _soldier_sphere_mesh: SphereMesh
var _builder_pool: Array[MeshInstance3D] = []
var _builder_pool_used: int = 0
var _builder_mesh: BoxMesh
var _marker_box_mesh: BoxMesh
var _road_seg_count: Dictionary = {}
var _road_nodes: Dictionary = {}
var _path_cache: Dictionary = {} # sid -> PackedInt32Array
var _preview: Node3D
var _preview_route: Node3D
var _preview_pins: Node3D
var _preview_material: StandardMaterial3D
var _preview_bridge_material: StandardMaterial3D
var _marker_pulse: float = 0.0
var _preview_path_sig: int = 0
var _preview_landing: Vector2i = Vector2i(-99999, -99999)
var _preview_click: Vector2i = Vector2i(-99999, -99999)
var _fluid_mat: StandardMaterial3D
var _fluid_tex: ImageTexture
var _fluid_img: Image
var _gpu_fluid_ready: bool = false
var _fluid_shader_mat: ShaderMaterial
var _pf_tex: ImageTexture
var _ph_tex: ImageTexture
var _land_tex_gpu: ImageTexture
var _pf_img_rf: Image
var _ph_img_rf: Image
var _gpu_ownership_ready: bool = false
var _ownership_shader_mat: ShaderMaterial
var _owner_tex_gpu: ImageTexture
var _owner_img_gpu: Image
var _owner_bytes_cache: PackedByteArray = PackedByteArray()
var _border_bytes_cache: PackedByteArray = PackedByteArray()
var _border_tex_gpu: ImageTexture
var _border_img_gpu: Image
var _surface_lut: PackedVector3Array = PackedVector3Array()
var _road_seg_pool: Array[MeshInstance3D] = []
var _link_seg_pool: Array[MeshInstance3D] = []
var _shared_road_box: BoxMesh
var _shared_link_box: BoxMesh
var _resource_link_phase: Dictionary = {}
var _land_mask: PackedByteArray = PackedByteArray()
var _cam_distance: float = WorldConquestConfigLib.CAMERA_DEFAULT_DISTANCE
var _yaw: float = -0.6
var _pitch: float = 0.35
var _dragging: bool = false
var _last_mouse: Vector2 = Vector2.ZERO
var _owner_gpu_upload_pending: bool = false
var _last_owner_gpu_upload_usec: int = 0
var _owner_gpu_upload_committed: bool = false
var _owner_overlay_patch_frame: int = -1
var _marker_sid_slot: Dictionary = {}


func setup(map_data) -> void:
	battle_data = map_data
	_land_mask = BattleTerritoryRustBackendLib.land_mask_from_map(map_data)
	_build_surface_lut()
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
	_globe_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	_fluid_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_fluid_tex = ImageTexture.create_from_image(_fluid_img)
	_fluid_mat = StandardMaterial3D.new()
	_fluid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fluid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Back-face culling halves fluid fragment work and stops far-side fluid
	# bleeding through the globe (no_depth_test draws over the terrain shell).
	_fluid_mat.cull_mode = BaseMaterial3D.CULL_BACK
	_fluid_mat.no_depth_test = true
	_fluid_mat.render_priority = 1
	_fluid_mat.albedo_texture = _fluid_tex
	_fluid_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_fluid_mi.material_override = _fluid_mat
	add_child(_fluid_mi)
	if WorldConquestConfigLib.OVERLAY_OWNERS_ONLY:
		_setup_gpu_ownership_material(w, h)
	else:
		_setup_gpu_fluid_material(w, h)
	_shared_road_box = BoxMesh.new()
	_shared_road_box.size = Vector3.ONE
	_shared_link_box = BoxMesh.new()
	_shared_link_box.size = Vector3.ONE
	_markers = Node3D.new()
	_markers.name = "Markers"
	add_child(_markers)
	# Pre-warm marker pool (after _markers node exists) to avoid creation hitch on state changes like outpost build complete.
	for _i in range(128):
		var node := MeshInstance3D.new()
		node.mesh = _marker_box_mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visible = false
		_markers.add_child(node)
		_marker_pool.append(node)
	_soldiers = Node3D.new()
	_soldiers.name = "Soldiers"
	add_child(_soldiers)
	_soldier_sphere_mesh = SphereMesh.new()
	_soldier_sphere_mesh.radius = 0.35
	_soldier_sphere_mesh.height = 0.7
	_builders = Node3D.new()
	_builders.name = "Builders"
	add_child(_builders)
	_builder_mesh = BoxMesh.new()
	_builder_mesh.size = Vector3(0.55, 0.35, 0.55)
	_effects = Node3D.new()
	_effects.name = "Effects"
	add_child(_effects)
	_roads = Node3D.new()
	_roads.name = "Roads"
	add_child(_roads)
	# Pre-warm a decent number of road segments in the pool.
	# Avoids creation + add_child cost on the frame when a long outpost road first completes (the "connect" event).
	# 256 is enough for several long paths; pool grows if needed.
	if _shared_road_box != null:
		for _i in range(256):
			var seg := MeshInstance3D.new()
			seg.mesh = _shared_road_box
			seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			seg.sorting_offset = 2.0
			seg.visible = false
			_roads.add_child(seg)
			_road_seg_pool.append(seg)
	_preview = Node3D.new()
	_preview.name = "Preview"
	add_child(_preview)
	_preview_route = Node3D.new()
	_preview_route.name = "Route"
	_preview.add_child(_preview_route)
	_preview_pins = Node3D.new()
	_preview_pins.name = "Pins"
	_preview.add_child(_preview_pins)
	_preview_material = StandardMaterial3D.new()
	_preview_material.albedo_color = Color(0.45, 0.72, 1.0, 0.38)
	_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview_bridge_material = StandardMaterial3D.new()
	_preview_bridge_material.albedo_color = Color(0.55, 0.78, 0.95, 0.42)
	_preview_bridge_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview_bridge_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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
	_road_material.no_depth_test = true
	_road_material.render_priority = ROAD_RENDER_PRIORITY
	_bridge_material = StandardMaterial3D.new()
	_bridge_material.albedo_color = BRIDGE_COLOR
	_bridge_material.roughness = 0.85
	_bridge_material.metallic = 0.05
	_bridge_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bridge_material.no_depth_test = true
	_bridge_material.render_priority = ROAD_RENDER_PRIORITY
	_resource_link_material = StandardMaterial3D.new()
	_resource_link_material.albedo_color = Color(0.72, 0.68, 0.38, 0.85)
	_resource_link_material.emission_enabled = true
	_resource_link_material.emission = Color(0.55, 0.5, 0.2)
	_resource_link_material.emission_energy_multiplier = 0.6
	_resource_link_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_resource_link_materials.clear()
	_resource_link_materials_linking.clear()
	for i in WorldConquestConfigLib.RESOURCE_TYPE_COUNT:
		var col: Color = WorldConquestConfigLib.RESOURCE_COLORS[i]
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color(col.r, col.g, col.b, 0.88)
		lmat.emission_enabled = true
		lmat.emission = col * 0.35
		lmat.emission_energy_multiplier = 0.6
		lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_resource_link_materials.append(lmat)
		var lmat_dim := StandardMaterial3D.new()
		lmat_dim.albedo_color = Color(col.r, col.g, col.b, 0.36)
		lmat_dim.emission_enabled = true
		lmat_dim.emission = col * 0.2
		lmat_dim.emission_energy_multiplier = 0.45
		lmat_dim.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lmat_dim.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_resource_link_materials_linking.append(lmat_dim)
	_road_seg_count.clear()
	_road_nodes.clear()
	_path_cache.clear()
	_resource_link_seg_count.clear()
	_resource_link_nodes.clear()
	_pulse_pool.clear()
	_marker_pool.clear()
	_marker_pool_used = 0
	_marker_box_mesh = BoxMesh.new()
	_marker_box_mesh.size = Vector3.ONE
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
	display_mask: PackedByteArray = PackedByteArray(),
) -> void:
	if battle_data == null or _fluid_tex == null:
		return
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	var mask: PackedByteArray = display_mask
	if mask.is_empty():
		mask = _land_mask
	var img: Image = null
	var rgba: PackedByteArray = BattleTerritoryRustBackendLib.bake_fluid_rgba(
		battle_data, pressure_friendly, pressure_hostile, 1.0, mask
	)
	if not rgba.is_empty() and rgba.size() == w * h * 4:
		_seal_rgba_longitude_seam(rgba, w, h)
		if _fluid_img == null or _fluid_img.get_width() != w or _fluid_img.get_height() != h:
			_fluid_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
		_fluid_img.set_data(w, h, false, Image.FORMAT_RGBA8, rgba)
		img = _fluid_img
	if img == null:
		img = BattleTileFluidFieldLib.build_fluid_image_from_powers(
			battle_data, pressure_friendly, pressure_hostile, 1.0, 0
		)
		if img == null:
			return
		_seal_texture_longitude_seam(img)
	_fluid_tex.update(img)


func apply_fluid_from_pressures_gpu(
	pressure_friendly: PackedFloat32Array,
	pressure_hostile: PackedFloat32Array,
	display_mask: PackedByteArray = PackedByteArray(),
	_visible_rect: Rect2i = Rect2i(),
	frame_peak: float = -1.0,
) -> void:
	if battle_data == null:
		return
	if _gpu_fluid_ready:
		_upload_pressure_textures(pressure_friendly, pressure_hostile, frame_peak)
		return
	apply_fluid_from_pressures(pressure_friendly, pressure_hostile, display_mask)


func _upload_pressure_textures(
	pressure_friendly: PackedFloat32Array,
	pressure_hostile: PackedFloat32Array,
	frame_peak: float = -1.0,
) -> void:
	if battle_data == null or _pf_img_rf == null or _ph_img_rf == null:
		return
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	var n: int = w * h
	if pressure_friendly.size() < n or pressure_hostile.size() < n:
		return
	var peak: float = frame_peak
	if peak <= 0.0:
		peak = 0.01
		for idx in range(n):
			peak = maxf(peak, maxf(pressure_friendly[idx], pressure_hostile[idx]))
	_upload_rf_image_from_pressure(_pf_img_rf, pressure_friendly, w, h)
	_upload_rf_image_from_pressure(_ph_img_rf, pressure_hostile, w, h)
	_pf_tex.update(_pf_img_rf)
	_ph_tex.update(_ph_img_rf)
	if _fluid_shader_mat != null:
		_fluid_shader_mat.set_shader_parameter("frame_peak", peak)


static func _upload_rf_image_from_pressure(
	img: Image, pressure: PackedFloat32Array, w: int, h: int
) -> void:
	var n: int = w * h
	if pressure.size() < n:
		return
	var bytes: PackedByteArray = pressure.to_byte_array()
	var need: int = n * 4
	if bytes.size() < need:
		return
	for gy in range(h):
		var row: int = gy * w * 4
		var last: int = row + (w - 1) * 4
		bytes[last] = bytes[row]
		bytes[last + 1] = bytes[row + 1]
		bytes[last + 2] = bytes[row + 2]
		bytes[last + 3] = bytes[row + 3]
	img.set_data(w, h, false, Image.FORMAT_RF, bytes.slice(0, need))


func _build_surface_lut() -> void:
	if battle_data == null:
		return
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	var n: int = w * h
	_surface_lut.resize(n)
	var base_r: float = WorldConquestConfigLib.GLOBE_RADIUS
	var hs: float = WorldConquestConfigLib.HEIGHT_SCALE
	for gy in range(h):
		for gx in range(w):
			var elev: float = battle_data.get_tile_height(gx, gy) * hs
			_surface_lut[gy * w + gx] = EarthGlobeMeshLib.grid_to_sphere(
				gx, gy, w, h, base_r + elev, 0.0
			)


func _setup_gpu_ownership_material(w: int, h: int) -> void:
	var shader: Shader = load("res://shaders/globe/ownership_display.gdshader")
	if shader == null or _fluid_mi == null:
		_gpu_ownership_ready = false
		if _fluid_mi != null:
			_fluid_mi.visible = false
		return
	_owner_img_gpu = Image.create(w, h, false, Image.FORMAT_R8)
	_owner_img_gpu.fill(Color(0, 0, 0))
	_owner_tex_gpu = ImageTexture.create_from_image(_owner_img_gpu)
	var land_img := Image.create(w, h, false, Image.FORMAT_R8)
	for gy in range(h):
		for gx in range(w):
			var idx: int = gy * w + gx
			var v: float = 1.0 if idx < _land_mask.size() and _land_mask[idx] != 0 else 0.0
			land_img.set_pixel(gx, gy, Color(v, 0, 0))
	_land_tex_gpu = ImageTexture.create_from_image(land_img)
	_ownership_shader_mat = ShaderMaterial.new()
	_ownership_shader_mat.shader = shader
	_border_img_gpu = Image.create(w, h, false, Image.FORMAT_R8)
	_border_img_gpu.fill(Color(0, 0, 0))
	_border_tex_gpu = ImageTexture.create_from_image(_border_img_gpu)
	_border_bytes_cache.resize(w * h)
	_ownership_shader_mat.set_shader_parameter("owner_map", _owner_tex_gpu)
	_ownership_shader_mat.set_shader_parameter("border_map", _border_tex_gpu)
	_ownership_shader_mat.set_shader_parameter("land_mask", _land_tex_gpu)
	_ownership_shader_mat.render_priority = 1
	_fluid_mi.material_override = _ownership_shader_mat
	_fluid_mi.visible = true
	_gpu_ownership_ready = true
	_gpu_fluid_ready = false


static func _owner_display_byte(owner: int) -> int:
	match owner:
		BattleTileControlLib.OWNER_FRIENDLY:
			return 128
		BattleTileControlLib.OWNER_HOSTILE:
			return 192
		BattleTileControlLib.OWNER_CONTESTED:
			return 255
		BattleTileControlLib.OWNER_NEUTRAL:
			return 0
		_:
			return 0


static func _owner_kind_from_byte(byte_v: int) -> int:
	if byte_v > 200:
		return 3
	if byte_v > 160:
		return 2
	if byte_v > 100:
		return 1
	if byte_v > 20:
		return 0
	return -1


func _neighbor_grid_coords(gx: int, gy: int, w: int, h: int) -> Array:
	var out: Array = []
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
	]
	for d in dirs:
		var nx: int = (gx + d.x + w) % w
		var ny: int = gy + d.y
		if ny < 0 or ny >= h:
			continue
		out.append(Vector2i(nx, ny))
	return out


func _is_border_cell(gx: int, gy: int, w: int, h: int) -> bool:
	var idx: int = gy * w + gx
	if idx < 0 or idx >= _owner_bytes_cache.size():
		return false
	if idx < _land_mask.size() and _land_mask[idx] == 0:
		return false
	var kind: int = _owner_kind_from_byte(int(_owner_bytes_cache[idx]))
	if kind < 0:
		return false
	for nxy in _neighbor_grid_coords(gx, gy, w, h):
		var ni: int = nxy.y * w + nxy.x
		if ni < 0 or ni >= _owner_bytes_cache.size():
			return true
		var nk: int = _owner_kind_from_byte(int(_owner_bytes_cache[ni]))
		if nk != kind:
			return true
	return false


func _rebuild_border_mask_full() -> void:
	if battle_data == null or _border_bytes_cache.is_empty():
		return
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	for gy in range(h):
		for gx in range(w):
			var idx: int = gy * w + gx
			_border_bytes_cache[idx] = 255 if _is_border_cell(gx, gy, w, h) else 0


func _update_border_mask_for_indices(indices: PackedInt32Array) -> void:
	if battle_data == null or _border_bytes_cache.is_empty() or indices.is_empty():
		return
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	var touch: Dictionary = {}
	for i in range(indices.size()):
		var idx: int = indices[i]
		if idx < 0 or idx >= w * h:
			continue
		var gx: int = idx % w
		var gy: int = idx / w
		touch[idx] = true
		for nxy in _neighbor_grid_coords(gx, gy, w, h):
			touch[nxy.y * w + nxy.x] = true
	for key in touch.keys():
		var tidx: int = int(key)
		var tgx: int = tidx % w
		var tgy: int = tidx / w
		_border_bytes_cache[tidx] = 255 if _is_border_cell(tgx, tgy, w, h) else 0


func _upload_owner_gpu_textures(force: bool = false) -> void:
	if not _gpu_ownership_ready or _owner_img_gpu == null or _owner_tex_gpu == null:
		return
	if not force:
		_owner_gpu_upload_pending = true
		return
	_commit_owner_gpu_textures(true)


func owner_gpu_upload_pending() -> bool:
	return _owner_gpu_upload_pending


func owner_overlay_patch_frame() -> int:
	return _owner_overlay_patch_frame


func _overlay_patch_blocks_gpu_commit() -> bool:
	if _owner_overlay_patch_frame < 0:
		return false
	var frame: int = Engine.get_process_frames()
	# Defer GPU commit on the patch frame and the next frame so overlay:delta CPU work
	# does not stack with texture upload on the same or immediately following frame.
	return frame >= _owner_overlay_patch_frame and frame <= _owner_overlay_patch_frame + 1


func flush_pending_owner_gpu_upload(defer_if_overlay_frame: bool = false) -> bool:
	if defer_if_overlay_frame or not _owner_gpu_upload_pending:
		return false
	if _overlay_patch_blocks_gpu_commit():
		return false
	var min_interval_usec: int = int(1_000_000.0 / WorldConquestConfigLib.OVERLAY_GPU_UPLOAD_MAX_HZ)
	var now_usec: int = Time.get_ticks_usec()
	if now_usec - _last_owner_gpu_upload_usec < min_interval_usec:
		return false
	_commit_owner_gpu_textures(false)
	return true


func consume_owner_gpu_upload_committed() -> bool:
	var committed := _owner_gpu_upload_committed
	_owner_gpu_upload_committed = false
	return committed


func _commit_owner_gpu_textures(allow_same_frame_as_patch: bool = false) -> void:
	if not _gpu_ownership_ready or battle_data == null or _owner_img_gpu == null or _owner_tex_gpu == null:
		return
	if not allow_same_frame_as_patch and _overlay_patch_blocks_gpu_commit():
		_owner_gpu_upload_pending = true
		return
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	_owner_img_gpu.set_data(w, h, false, Image.FORMAT_R8, _owner_bytes_cache)
	_owner_tex_gpu.update(_owner_img_gpu)
	if _border_img_gpu != null and _border_tex_gpu != null and not _border_bytes_cache.is_empty():
		_border_img_gpu.set_data(w, h, false, Image.FORMAT_R8, _border_bytes_cache)
		_border_tex_gpu.update(_border_img_gpu)
	_owner_gpu_upload_pending = false
	_last_owner_gpu_upload_usec = Time.get_ticks_usec()
	_owner_gpu_upload_committed = true


func apply_ownership_overlay(owners: PackedByteArray) -> void:
	# Fallback / CPU-backend path. 
	# In normal Rust live play we avoid this expensive loop entirely:
	# - Regular outpost connect/build → only cheap per-changed delta (apply_ownership_overlay_delta).
	# - Rare full cases (load, real bridge land opens) → callers now use apply_ownership_display_bytes()
	#   which gets pre-baked bytes from Rust (get_owner_display_r8) so zero 65k GDScript work.
	if not _gpu_ownership_ready or battle_data == null or _owner_img_gpu == null:
		return
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	var n: int = w * h
	if owners.size() < n:
		return
	if _owner_bytes_cache.size() != n:
		_owner_bytes_cache.resize(n)
	for idx in range(n):
		if idx < _land_mask.size() and _land_mask[idx] == 0:
			_owner_bytes_cache[idx] = 0
			continue
		_owner_bytes_cache[idx] = _owner_display_byte(int(owners[idx]))
	for gy in range(h):
		var row: int = gy * w
		_owner_bytes_cache[row + w - 1] = _owner_bytes_cache[row]
	_rebuild_border_mask_full()
	_owner_overlay_patch_frame = -1
	_upload_owner_gpu_textures(true)

## Fast path for when we have pre-baked R8 display bytes from Rust (no 65k GDScript loop at all).
## Preferred for the remaining "full refresh" cases (load, corridor completes).
func apply_ownership_display_bytes(bytes: PackedByteArray) -> void:
	if not _gpu_ownership_ready or battle_data == null or _owner_img_gpu == null:
		return
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	var n: int = w * h
	if bytes.size() != n:
		return
	if _owner_bytes_cache.size() != n:
		_owner_bytes_cache.resize(n)
	for i in range(n):
		_owner_bytes_cache[i] = bytes[i]
	_border_bytes_cache.resize(n)
	_rebuild_border_mask_full()
	_owner_overlay_patch_frame = -1
	_upload_owner_gpu_textures(true)


func apply_ownership_overlay_delta(
	indices: PackedInt32Array, values: PackedByteArray
) -> void:
	if not _gpu_ownership_ready or battle_data == null or _owner_img_gpu == null:
		return
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	var n: int = mini(indices.size(), values.size())
	if n <= 0:
		return
	if _owner_bytes_cache.size() != w * h:
		_owner_bytes_cache.resize(w * h)
	if _border_bytes_cache.size() != w * h:
		_border_bytes_cache.resize(w * h)
	for i in range(n):
		var idx: int = indices[i]
		if idx < 0 or idx >= w * h:
			continue
		var byte_v: int = 0
		if idx >= _land_mask.size() or _land_mask[idx] != 0:
			byte_v = _owner_display_byte(int(values[i]))
		_owner_bytes_cache[idx] = byte_v
	# Keep longitude seam consistent for repeat sampling on the globe.
	for gy2 in range(h):
		var row: int = gy2 * w
		_owner_bytes_cache[row + w - 1] = _owner_bytes_cache[row]
	if n > 256:
		_rebuild_border_mask_full()
	else:
		_update_border_mask_for_indices(indices)
	_owner_overlay_patch_frame = Engine.get_process_frames()
	_upload_owner_gpu_textures()


func _setup_gpu_fluid_material(w: int, h: int) -> void:
	var shader: Shader = load("res://shaders/globe/fluid_display.gdshader")
	if shader == null:
		_gpu_fluid_ready = false
		return
	_pf_img_rf = Image.create(w, h, false, Image.FORMAT_RF)
	_ph_img_rf = Image.create(w, h, false, Image.FORMAT_RF)
	_pf_img_rf.fill(Color(0, 0, 0))
	_ph_img_rf.fill(Color(0, 0, 0))
	_pf_tex = ImageTexture.create_from_image(_pf_img_rf)
	_ph_tex = ImageTexture.create_from_image(_ph_img_rf)
	var land_img := Image.create(w, h, false, Image.FORMAT_R8)
	for gy in range(h):
		for gx in range(w):
			var idx: int = gy * w + gx
			var v: float = 1.0 if idx < _land_mask.size() and _land_mask[idx] != 0 else 0.0
			land_img.set_pixel(gx, gy, Color(v, 0, 0))
	_land_tex_gpu = ImageTexture.create_from_image(land_img)
	_fluid_shader_mat = ShaderMaterial.new()
	_fluid_shader_mat.shader = shader
	_fluid_shader_mat.set_shader_parameter("pressure_friendly", _pf_tex)
	_fluid_shader_mat.set_shader_parameter("pressure_hostile", _ph_tex)
	_fluid_shader_mat.set_shader_parameter("land_mask", _land_tex_gpu)
	_fluid_shader_mat.set_shader_parameter("frame_peak", 10000.0)
	_fluid_shader_mat.set_shader_parameter("power_scale", 1.0)
	_fluid_shader_mat.render_priority = 1
	if _fluid_mi != null:
		_fluid_mi.material_override = _fluid_shader_mat
	_gpu_fluid_ready = true


static func _seal_rgba_longitude_seam(rgba: PackedByteArray, w: int, h: int) -> void:
	if w < 2:
		return
	for gy in range(h):
		var row: int = gy * w * 4
		var last: int = row + (w - 1) * 4
		rgba[last] = rgba[row]
		rgba[last + 1] = rgba[row + 1]
		rgba[last + 2] = rgba[row + 2]
		rgba[last + 3] = rgba[row + 3]


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
		var linking: bool = phase == WorldConquestResourcesLib.PHASE_LINKING
		var prev_phase: String = str(_resource_link_phase.get(dep_id, ""))
		if prev_phase != phase:
			_resource_link_phase[dep_id] = phase
			if prev_phase == WorldConquestResourcesLib.PHASE_LINKING and phase == WorldConquestResourcesLib.PHASE_HAULING:
				_set_resource_link_opaque(dep_id, type_i)
		var need_segs: int = maxi(built - 1, 0)
		var have_segs: int = int(_resource_link_seg_count.get(dep_id, 0))
		if need_segs <= have_segs:
			continue
		for i in range(have_segs, need_segs):
			var a: Vector2i = WorldConquestOutpostBuildLib.grid_from_packed_key(link_path[i], w)
			var b: Vector2i = WorldConquestOutpostBuildLib.grid_from_packed_key(link_path[i + 1], w)
			_add_resource_link_segment(a, b, type_i, dep_id, linking)
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


func set_marker_pulse(t: float) -> void:
	_marker_pulse = t


func clear_placement_preview() -> void:
	if _preview_route != null:
		for c in _preview_route.get_children():
			c.queue_free()
	if _preview_pins != null:
		for c in _preview_pins.get_children():
			c.queue_free()
	_preview_path_sig = 0
	_preview_landing = Vector2i(-99999, -99999)
	_preview_click = Vector2i(-99999, -99999)


func _path_preview_signature(path_packed: PackedInt32Array) -> int:
	var sig: int = path_packed.size()
	for i in mini(path_packed.size(), 8):
		sig = (sig * 31) ^ path_packed[i]
	if path_packed.size() > 0:
		sig = (sig * 31) ^ path_packed[path_packed.size() - 1]
	return sig


func set_placement_preview(
	path_packed: PackedInt32Array,
	landing: Vector2i,
	click_raw: Vector2i,
	active: bool,
	is_corridor: bool = false,
) -> void:
	if not active or _preview == null or battle_data == null or landing.x < 0:
		clear_placement_preview()
		return
	var path_sig: int = _path_preview_signature(path_packed)
	var route_dirty: bool = (
		path_sig != _preview_path_sig or landing != _preview_landing or click_raw != _preview_click
	)
	if route_dirty:
		for c in _preview_route.get_children():
			c.queue_free()
		var w: int = battle_data.grid_width
		var draw_path: PackedInt32Array = WorldConquestOutpostBuildLib.subsample_path_for_preview(
			path_packed, WorldConquestConfigLib.OUTPOST_PREVIEW_MAX_SEGMENTS
		)
		if draw_path.size() >= 2:
			for i in range(draw_path.size() - 1):
				var a: Vector2i = WorldConquestOutpostBuildLib.grid_from_packed_key(draw_path[i], w)
				var b: Vector2i = WorldConquestOutpostBuildLib.grid_from_packed_key(draw_path[i + 1], w)
				_add_preview_segment_to(_preview_route, a, b)
		_preview_path_sig = path_sig
		_preview_landing = landing
		_preview_click = click_raw
	for c in _preview_pins.get_children():
		c.queue_free()
	var pulse: float = 0.65 + 0.35 * sin(_marker_pulse * TAU)
	var landing_col: Color = (
		Color(0.35, 0.92, 0.82, pulse) if is_corridor else Color(0.95, 0.72, 0.22, pulse)
	)
	_add_capital_marker_to(_preview_pins, landing, landing_col, 1.15, pulse)
	if click_raw.x >= 0 and click_raw != landing:
		_add_capital_marker_to(
			_preview_pins, click_raw, Color(0.55, 0.55, 0.58, 0.45), 0.55, 0.45
		)


func refresh_markers(
	structures: Array, home_player: Vector2i, home_enemy: Vector2i, changed_sids: Array = []
) -> void:
	if _markers == null:
		return
	if not changed_sids.is_empty() and not _marker_sid_slot.is_empty():
		_refresh_markers_for_sids(structures, home_player, home_enemy, changed_sids)
		return
	# Pooled markers: update transforms/materials in place (no node/mesh/material churn
	# during the 4 Hz construction-pulse refresh).
	_marker_pool_used = 0
	_marker_sid_slot.clear()
	_place_pooled_marker(home_player, Color(0.2, 0.55, 1.0), 2.2)
	_place_pooled_marker(home_enemy, Color(0.95, 0.3, 0.22), 2.2)
	var pulse: float = 0.55 + 0.45 * sin(_marker_pulse * TAU)
	for st: Dictionary in structures:
		var kind: String = str(st.get("kind", ""))
		if not WorldConquestOutpostBuildLib.is_corridor_path_kind(kind):
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
				if kind == WorldConquestOutpostBuildLib.KIND_CORRIDOR_LINK:
					col = Color(0.35, 0.92, 0.82, pulse)
				else:
					col = Color(0.95, 0.62, 0.18, pulse)
				scale_f = 1.05 + 0.12 * sin(_marker_pulse * TAU)
				alpha = pulse
			WorldConquestOutpostBuildLib.STATE_BUILDING:
				if kind == WorldConquestOutpostBuildLib.KIND_CORRIDOR_LINK:
					continue
				var build_sec: float = WorldConquestOutpostBuildLib.build_sec_for_kind(kind)
				var rem: float = float(st.get("build_remaining", build_sec))
				var prog: float = 1.0 - clampf(rem / build_sec, 0.0, 1.0)
				if kind == WorldConquestOutpostBuildLib.KIND_BARRACKS:
					col = Color(0.55, 0.38, 0.22).lerp(Color(0.85, 0.55, 0.28), prog)
				else:
					col = Color(0.3, 0.45, 0.62).lerp(Color(0.25, 0.65, 1.0), prog)
				scale_f = lerpf(0.78, 1.0, prog)
				alpha = lerpf(0.65, 1.0, prog)
			_:
				if kind == WorldConquestOutpostBuildLib.KIND_BARRACKS:
					col = Color(0.82, 0.58, 0.24) if team == 1 else Color(0.9, 0.45, 0.28)
				else:
					col = Color(0.25, 0.65, 1.0) if team == 1 else Color(1.0, 0.4, 0.3)
		if state != WorldConquestOutpostBuildLib.STATE_ACTIVE and hp_frac < 1.0:
			col = col.lerp(Color(0.92, 0.28, 0.18), 1.0 - hp_frac)
			scale_f *= lerpf(0.85, 1.0, hp_frac)
		var sid: int = int(st.get("id", -1))
		if sid >= 0:
			_marker_sid_slot[sid] = _marker_pool_used
		_place_pooled_marker(Vector2i(gx, gy), col, scale_f, alpha)
	for i in range(_marker_pool_used, _marker_pool.size()):
		_marker_pool[i].visible = false


func refresh_connecting_markers(structures: Array, home_player: Vector2i, home_enemy: Vector2i) -> void:
	if _markers == null:
		return
	if _marker_sid_slot.is_empty():
		refresh_markers(structures, home_player, home_enemy)
		return
	var pulse_sids: Array[int] = []
	for st: Dictionary in structures:
		if not WorldConquestOutpostBuildLib.is_corridor_path_kind(str(st.get("kind", ""))):
			continue
		var state: String = str(st.get("state", WorldConquestOutpostBuildLib.STATE_ACTIVE))
		if (
			state == WorldConquestOutpostBuildLib.STATE_CONNECTING
			or state == WorldConquestOutpostBuildLib.STATE_BUILDING
		):
			var sid: int = int(st.get("id", -1))
			if sid >= 0:
				pulse_sids.append(sid)
	if pulse_sids.is_empty():
		return
	_refresh_markers_for_sids(structures, home_player, home_enemy, pulse_sids)


func _refresh_markers_for_sids(
	structures: Array, home_player: Vector2i, home_enemy: Vector2i, changed_sids: Array
) -> void:
	var changed_set: Dictionary = {}
	for sid_v in changed_sids:
		changed_set[int(sid_v)] = true
	var pulse: float = 0.55 + 0.45 * sin(_marker_pulse * TAU)
	for st: Dictionary in structures:
		var sid: int = int(st.get("id", -1))
		if sid < 0 or not changed_set.has(sid):
			continue
		if not _marker_sid_slot.has(sid):
			refresh_markers(structures, home_player, home_enemy)
			return
		var slot: int = int(_marker_sid_slot[sid])
		if slot < 0 or slot >= _marker_pool.size():
			continue
		_apply_structure_marker_to_slot(st, slot, pulse)


func _apply_structure_marker_to_slot(st: Dictionary, slot: int, pulse: float) -> void:
	var kind: String = str(st.get("kind", ""))
	if not WorldConquestOutpostBuildLib.is_corridor_path_kind(kind):
		return
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
			if kind == WorldConquestOutpostBuildLib.KIND_CORRIDOR_LINK:
				col = Color(0.35, 0.92, 0.82, pulse)
			else:
				col = Color(0.95, 0.62, 0.18, pulse)
			scale_f = 1.05 + 0.12 * sin(_marker_pulse * TAU)
			alpha = pulse
		WorldConquestOutpostBuildLib.STATE_BUILDING:
			if kind == WorldConquestOutpostBuildLib.KIND_CORRIDOR_LINK:
				return
			var build_sec: float = WorldConquestOutpostBuildLib.build_sec_for_kind(kind)
			var rem: float = float(st.get("build_remaining", build_sec))
			var prog: float = 1.0 - clampf(rem / build_sec, 0.0, 1.0)
			if kind == WorldConquestOutpostBuildLib.KIND_BARRACKS:
				col = Color(0.55, 0.38, 0.22).lerp(Color(0.85, 0.55, 0.28), prog)
			else:
				col = Color(0.3, 0.45, 0.62).lerp(Color(0.25, 0.65, 1.0), prog)
			scale_f = lerpf(0.78, 1.0, prog)
			alpha = lerpf(0.65, 1.0, prog)
		_:
			if kind == WorldConquestOutpostBuildLib.KIND_BARRACKS:
				col = Color(0.82, 0.58, 0.24) if team == 1 else Color(0.9, 0.45, 0.28)
			else:
				col = Color(0.25, 0.65, 1.0) if team == 1 else Color(1.0, 0.4, 0.3)
	if state != WorldConquestOutpostBuildLib.STATE_ACTIVE and hp_frac < 1.0:
		col = col.lerp(Color(0.92, 0.28, 0.18), 1.0 - hp_frac)
		scale_f *= lerpf(0.85, 1.0, hp_frac)
	var node: MeshInstance3D = _marker_pool[slot]
	node.visible = true
	node.position = _grid_surface_pos(Vector2i(gx, gy), 1.5)
	node.scale = Vector3.ONE * (1.8 * scale_f)
	var mat := node.material_override as StandardMaterial3D
	mat.albedo_color = Color(col.r, col.g, col.b, alpha)
	mat.emission = Color(col.r, col.g, col.b) * 0.5
	mat.transparency = (
		BaseMaterial3D.TRANSPARENCY_ALPHA
		if alpha < 0.99
		else BaseMaterial3D.TRANSPARENCY_DISABLED
	)


func grid_lerp_surface_pos(grid_a: Vector2i, grid_b: Vector2i, t: float, lift: float) -> Vector3:
	var ta: float = clampf(t, 0.0, 1.0)
	var pos_a: Vector3 = _grid_surface_pos(grid_a, lift)
	var pos_b: Vector3 = _grid_surface_pos(grid_b, lift)
	return pos_a.lerp(pos_b, ta)


func grid_float_surface_pos(gx_f: float, gy_f: float, lift: float) -> Vector3:
	if battle_data == null:
		return Vector3.ZERO
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	var gx: int = int(floor(gx_f)) % w
	if gx < 0:
		gx += w
	var gy: int = clampi(int(floor(gy_f)), 0, h - 1)
	var fx: float = gx_f - floor(gx_f)
	var fy: float = gy_f - float(gy)
	var gx2: int = (gx + 1) % w
	var gy2: int = clampi(gy + 1, 0, h - 1)
	var p00: Vector3 = _grid_surface_pos(Vector2i(gx, gy), lift)
	var p10: Vector3 = _grid_surface_pos(Vector2i(gx2, gy), lift)
	var p01: Vector3 = _grid_surface_pos(Vector2i(gx, gy2), lift)
	var p11: Vector3 = _grid_surface_pos(Vector2i(gx2, gy2), lift)
	var top: Vector3 = p00.lerp(p10, fx)
	var bot: Vector3 = p01.lerp(p11, fx)
	return top.lerp(bot, clampf(fy, 0.0, 1.0))


func sync_builders(world_positions: Array, teams: PackedByteArray) -> void:
	if _builders == null:
		return
	_builder_pool_used = 0
	var n: int = mini(world_positions.size(), teams.size())
	for i in range(n):
		var pos: Vector3 = world_positions[i]
		if pos == Vector3.ZERO:
			continue
		var team: int = int(teams[i])
		var col: Color = (
			Color(0.45, 0.95, 1.0) if team == BattleTileControlLib.OWNER_FRIENDLY
			else Color(1.0, 0.55, 0.38)
		)
		_place_pooled_builder(pos, col)
	for j in range(_builder_pool_used, _builder_pool.size()):
		_builder_pool[j].visible = false


func _place_pooled_builder(pos: Vector3, color: Color) -> void:
	if _builders == null:
		return
	while _builder_pool.size() <= _builder_pool_used:
		var node := MeshInstance3D.new()
		node.mesh = _builder_mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.material_override = StandardMaterial3D.new()
		var mat := node.material_override as StandardMaterial3D
		mat.emission_enabled = true
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_builders.add_child(node)
		_builder_pool.append(node)
	var box: MeshInstance3D = _builder_pool[_builder_pool_used]
	_builder_pool_used += 1
	box.visible = true
	box.position = pos
	var mat2 := box.material_override as StandardMaterial3D
	mat2.albedo_color = color
	mat2.emission = color * 0.65


func sync_soldiers(teams: PackedByteArray, gx: PackedInt32Array, gy: PackedInt32Array) -> void:
	if _soldiers == null:
		return
	_soldier_pool_used = 0
	var n: int = mini(teams.size(), mini(gx.size(), gy.size()))
	for i in range(n):
		var grid := Vector2i(gx[i], gy[i])
		if grid.x < 0:
			continue
		var team: int = int(teams[i])
		var col: Color = Color(0.35, 0.82, 1.0) if team == 1 else Color(1.0, 0.42, 0.32)
		_place_pooled_soldier(grid, col)
	for j in range(_soldier_pool_used, _soldier_pool.size()):
		_soldier_pool[j].visible = false


func _place_pooled_soldier(grid: Vector2i, color: Color) -> void:
	if _soldiers == null or battle_data == null or grid.x < 0:
		return
	while _soldier_pool.size() <= _soldier_pool_used:
		var node := MeshInstance3D.new()
		node.mesh = _soldier_sphere_mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.material_override = StandardMaterial3D.new()
		(node.material_override as StandardMaterial3D).emission_enabled = true
		_soldiers.add_child(node)
		_soldier_pool.append(node)
	var sphere: MeshInstance3D = _soldier_pool[_soldier_pool_used]
	_soldier_pool_used += 1
	sphere.visible = true
	sphere.position = _grid_surface_pos(grid, 1.85)
	var mat := sphere.material_override as StandardMaterial3D
	mat.albedo_color = color
	mat.emission = color * 0.55
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func sync_roads(structures: Array, changed_sids: Array = []) -> void:
	if _roads == null or battle_data == null:
		return
	var incremental: bool = not changed_sids.is_empty()
	var changed_set: Dictionary = {}
	if incremental:
		for sid_v in changed_sids:
			changed_set[int(sid_v)] = true
	var live_ids: Dictionary = {}
	for st: Dictionary in structures:
		if not WorldConquestOutpostBuildLib.is_corridor_path_kind(str(st.get("kind", ""))):
			continue
		var sid: int = int(st.get("id", -1))
		if sid < 0:
			continue
		live_ids[sid] = true
		if not incremental or changed_set.has(sid):
			_sync_outpost_road(st, sid)
	for corridor: Dictionary in battle_data.bridge_corridors:
		var sid: int = int(corridor.get("id", -1))
		if sid < 0:
			continue
		live_ids[sid] = true
		if not incremental or changed_set.has(sid):
			var pseudo: Dictionary = corridor.duplicate()
			pseudo["state"] = WorldConquestOutpostBuildLib.STATE_ACTIVE
			_sync_outpost_road(pseudo, sid)
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
			seg.visible = false
			_road_seg_pool.append(seg as MeshInstance3D)
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
			seg.visible = false
			_link_seg_pool.append(seg as MeshInstance3D)
	_resource_link_nodes.erase(dep_id)
	_resource_link_seg_count.erase(dep_id)
	_resource_link_phase.erase(dep_id)


func _set_resource_link_opaque(dep_id: int, type_i: int) -> void:
	var mat_i: int = clampi(type_i, 0, _resource_link_materials.size() - 1)
	var mat: Material = (
		_resource_link_materials[mat_i]
		if not _resource_link_materials.is_empty()
		else _resource_link_material
	)
	for seg in _resource_link_nodes.get(dep_id, []):
		if is_instance_valid(seg):
			(seg as MeshInstance3D).material_override = mat


func _ensure_pulse_pool() -> void:
	var want: int = WorldConquestConfigLib.RESOURCE_MAX_VISUAL_PULSES
	while _pulse_pool.size() < want:
		var pulse := MeshInstance3D.new()
		pulse.mesh = _pulse_sphere_mesh
		pulse.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pulse.visible = false
		_resource_pulses.add_child(pulse)
		_pulse_pool.append(pulse)


func _add_resource_link_segment(
	a: Vector2i, b: Vector2i, type_i: int, dep_id: int, linking: bool = false
) -> void:
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
	var seg: MeshInstance3D
	if _link_seg_pool.is_empty():
		seg = MeshInstance3D.new()
		seg.mesh = _shared_link_box
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_resource_links.add_child(seg)
	else:
		seg = _link_seg_pool.pop_back()
		seg.visible = true
	var mat_i: int = clampi(type_i, 0, _resource_link_materials.size() - 1)
	if linking and not _resource_link_materials_linking.is_empty():
		seg.material_override = _resource_link_materials_linking[mat_i]
	elif not _resource_link_materials.is_empty():
		seg.material_override = _resource_link_materials[mat_i]
	else:
		seg.material_override = _resource_link_material
	seg.transform = Transform3D(
		Basis(x_axis * 0.18, y_axis * length, z_axis * 0.18),
		(pos_a + pos_b) * 0.5,
	)
	if not _resource_link_nodes.has(dep_id):
		_resource_link_nodes[dep_id] = []
	(_resource_link_nodes[dep_id] as Array).append(seg)


func _place_pooled_marker(
	grid: Vector2i, color: Color, scale_f: float, alpha: float = 1.0
) -> void:
	if _markers == null or battle_data == null or grid.x < 0:
		return
	while _marker_pool.size() <= _marker_pool_used:
		var node := MeshInstance3D.new()
		node.mesh = _marker_box_mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.material_override = StandardMaterial3D.new()
		(node.material_override as StandardMaterial3D).emission_enabled = true
		_markers.add_child(node)
		_marker_pool.append(node)
	var box: MeshInstance3D = _marker_pool[_marker_pool_used]
	_marker_pool_used += 1
	box.visible = true
	box.position = _grid_surface_pos(grid, 1.5)
	box.scale = Vector3.ONE * (1.8 * scale_f)
	var mat := box.material_override as StandardMaterial3D
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.emission = Color(color.r, color.g, color.b) * 0.5
	mat.transparency = (
		BaseMaterial3D.TRANSPARENCY_ALPHA
		if alpha < 0.99
		else BaseMaterial3D.TRANSPARENCY_DISABLED
	)


func _add_capital_marker_to(
	parent: Node3D, grid: Vector2i, color: Color, scale_f: float, alpha: float = 1.0
) -> void:
	if parent == null or battle_data == null or grid.x < 0:
		return
	var pos: Vector3 = _grid_surface_pos(grid, 1.5)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8 * scale_f, 1.8 * scale_f, 1.8 * scale_f)
	box.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b) * 0.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 0.99 else BaseMaterial3D.TRANSPARENCY_DISABLED
	box.material_override = mat
	box.position = pos
	parent.add_child(box)


func _add_preview_segment(a: Vector2i, b: Vector2i) -> void:
	_add_preview_segment_to(_preview_route, a, b)


func _add_preview_segment_to(parent: Node3D, a: Vector2i, b: Vector2i) -> void:
	if battle_data == null or parent == null or a.x < 0 or b.x < 0:
		return
	var is_bridge: bool = (
		WorldConquestOutpostBuildLib.is_water_cell(battle_data, a.x, a.y)
		or WorldConquestOutpostBuildLib.is_water_cell(battle_data, b.x, b.y)
	)
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
	var thickness: float = BRIDGE_THICKNESS * 0.85 if is_bridge else ROAD_THICKNESS * 0.85
	bm.size = Vector3(thickness, length, thickness)
	seg.mesh = bm
	seg.material_override = _preview_bridge_material if is_bridge else _preview_material
	seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	seg.transform = Transform3D(Basis(x_axis, y_axis, z_axis), (pos_a + pos_b) * 0.5)
	parent.add_child(seg)


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
	var seg: MeshInstance3D
	if _road_seg_pool.is_empty():
		seg = MeshInstance3D.new()
		seg.mesh = _shared_road_box
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		seg.sorting_offset = 2.0
		_roads.add_child(seg)
	else:
		seg = _road_seg_pool.pop_back()
		seg.visible = true
	var thickness: float = BRIDGE_THICKNESS if is_bridge else ROAD_THICKNESS
	seg.material_override = _bridge_material if is_bridge else _road_material
	seg.transform = Transform3D(
		Basis(x_axis * thickness, y_axis * length, z_axis * thickness),
		(pos_a + pos_b) * 0.5,
	)
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
	if battle_data == null or grid.x < 0:
		return Vector3.ZERO
	var w: int = battle_data.grid_width
	var idx: int = grid.y * w + grid.x
	if idx >= 0 and idx < _surface_lut.size():
		var base: Vector3 = _surface_lut[idx]
		if lift <= 0.001:
			return base
		return base + base.normalized() * lift
	var elev: float = battle_data.get_tile_height(grid.x, grid.y) * WorldConquestConfigLib.HEIGHT_SCALE
	return EarthGlobeMeshLib.grid_to_sphere(
		grid.x, grid.y, w, battle_data.grid_height,
		WorldConquestConfigLib.GLOBE_RADIUS + elev + lift, 0.0
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
	if is_inside_tree():
		camera.look_at(Vector3.ZERO, Vector3.UP)
	else:
		camera.look_at_from_position(offset, Vector3.ZERO, Vector3.UP)
