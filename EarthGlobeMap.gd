class_name EarthGlobeMap
extends Node3D

const BattleTileFluidFieldLib := preload("res://BattleTileFluidField.gd")
const BattleTileControlLib := preload("res://BattleTileControl.gd")
const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")
const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
const EarthGlobeMeshLib := preload("res://EarthGlobeMesh.gd")
const EarthGlobeRoadsLib := preload("res://EarthGlobeRoads.gd")
const PlanetVisualBakeLib := preload("res://PlanetVisualBake.gd")
const WorldConquestMapGeneratorLib := preload("res://WorldConquestMapGenerator.gd")
const WorldConquestOutpostBuildLib := preload("res://WorldConquestOutpostBuild.gd")
const WorldConquestResourcesLib := preload("res://WorldConquestResources.gd")
const WorldMapCatalogLib := preload("res://WorldMapCatalog.gd")
const _TERRAIN_SHADER: Shader = preload("res://shaders/globe/terrain_display.gdshader")
const _ATMOSPHERE_SHADER: Shader = preload("res://shaders/globe/atmosphere_rim.gdshader")

const ROAD_COLOR := Color(0.52, 0.52, 0.54)
const BRIDGE_COLOR := Color(0.62, 0.64, 0.68)
const ROAD_THICKNESS := 0.32
const BRIDGE_THICKNESS := 0.42
const ROAD_SURFACE_LIFT := 2.75
const ROAD_RENDER_PRIORITY := 8
const RESOURCE_RENDER_PRIORITY := 6
const MARKER_RENDER_PRIORITY := 7
const UNIT_RENDER_PRIORITY := 10
## Billboard pixel art (res://assets/units). pixel_size ≈ world meters per texture pixel.
const SOLDIER_SPRITE_PIXEL_SIZE := 0.0055
const BOMBER_SPRITE_PIXEL_SIZE := 0.0065
const SOLDIER_SURFACE_LIFT := 1.85
const TEX_SOLDIER_FRIENDLY: Texture2D = preload("res://assets/units/soldier_friendly.png")
const TEX_SOLDIER_HOSTILE: Texture2D = preload("res://assets/units/soldier_hostile.png")
const TEX_BOMBER_FRIENDLY: Texture2D = preload("res://assets/units/bomber_friendly.png")
const TEX_BOMBER_HOSTILE: Texture2D = preload("res://assets/units/bomber_hostile.png")
## B3/I4: prealloc MultiMesh capacity (EarthGlobeRoads.MIN_CAPACITY). Grow always reseeds.

@onready var camera: Camera3D = $Camera3D

var battle_data = null
var _world_map_id: String = WorldMapCatalogLib.DEFAULT_MAP_ID
var _globe_mi: MeshInstance3D
var _fluid_mi: MeshInstance3D
var _atmosphere_mi: MeshInstance3D
var _terrain_shader_mat: ShaderMaterial
var _albedo_tex: ImageTexture
var _height_tex: ImageTexture
var _markers: Node3D
var _soldiers: Node3D
var _bombers: Node3D
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
var _soldier_pool: Array[Sprite3D] = []
var _soldier_pool_used: int = 0
var _bomber_pool: Array[Sprite3D] = []
var _bomber_pool_used: int = 0
var _bomb_drop_mesh: SphereMesh
var _builder_pool: Array[MeshInstance3D] = []
var _builder_pool_used: int = 0
var _builder_mesh: BoxMesh
var _marker_box_mesh: BoxMesh
var _road_land_mm: MultiMeshInstance3D
var _road_bridge_mm: MultiMeshInstance3D
## Live instance counts (MultiMesh.instance_count is capacity; visible_instance_count is drawn).
## Authoritative transforms live in _road_cache_* / _network_road_* (rebuild source on grow).
var _road_mm_land_used: int = 0
var _road_mm_bridge_used: int = 0
## Keep in sync with EarthGlobeRoads.MIN_CAPACITY (prealloc; grow always reseeds).
const _ROAD_MM_MIN_CAPACITY := 4096
var _road_cache_land: Dictionary = {}
var _road_cache_bridge: Dictionary = {}
var _road_cached_seg_total: Dictionary = {}
var _network_built_cells: Dictionary = {}
var _network_road_land: Array[Transform3D] = []
var _network_road_bridge: Array[Transform3D] = []
var _path_cache: Dictionary = {} # sid -> PackedInt32Array
var _preview: Node3D
var _preview_route: Node3D
var _preview_pins: Node3D
var _preview_material: StandardMaterial3D
var _preview_bridge_material: StandardMaterial3D
var _marker_pulse: float = 0.0
## B8/H5: 1.0 = config mesh density; lower = fewer globe/fluid quads (rebuild via setup).
var _mesh_detail_scale: float = 1.0
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


func setup(map_data, map_id: String = WorldMapCatalogLib.DEFAULT_MAP_ID) -> void:
	battle_data = map_data
	_world_map_id = WorldMapCatalogLib.resolve_map_id(map_id)
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
	# B8/H5: mesh density from config knobs (detail scale clamps GPU cost under load).
	# GLOBE_RENDER_SCALE is applied by WorldConquestScreen on SubViewport size, not here.
	_globe_mi = MeshInstance3D.new()
	_globe_mi.name = "Globe"
	_globe_mi.mesh = _build_globe_mesh_for_detail(false)
	_globe_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply_terrain_material()
	add_child(_globe_mi)
	_add_atmosphere_shell()
	_fluid_mi = MeshInstance3D.new()
	_fluid_mi.name = "Fluid"
	_fluid_mi.mesh = _build_globe_mesh_for_detail(true)
	_fluid_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fluid_mi.sorting_offset = 0.0
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	_fluid_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_fluid_tex = ImageTexture.create_from_image(_fluid_img)
	_fluid_mat = StandardMaterial3D.new()
	_fluid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fluid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Depth-tested land overlay; cull back so far-side faces do not punch through ocean.
	_fluid_mat.cull_mode = BaseMaterial3D.CULL_BACK
	_fluid_mat.no_depth_test = false
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
	_marker_box_mesh = BoxMesh.new()
	_marker_box_mesh.size = Vector3.ONE
	_pulse_sphere_mesh = SphereMesh.new()
	_pulse_sphere_mesh.radius = 0.38
	_pulse_sphere_mesh.height = 0.76
	# Road materials before MultiMesh setup (material_override on MMI).
	_road_material = StandardMaterial3D.new()
	_road_material.albedo_color = ROAD_COLOR
	_road_material.roughness = 0.95
	_road_material.metallic = 0.0
	_road_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_road_material.no_depth_test = false
	_road_material.render_priority = ROAD_RENDER_PRIORITY
	_bridge_material = StandardMaterial3D.new()
	_bridge_material.albedo_color = BRIDGE_COLOR
	_bridge_material.roughness = 0.85
	_bridge_material.metallic = 0.05
	_bridge_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bridge_material.no_depth_test = false
	_bridge_material.render_priority = ROAD_RENDER_PRIORITY
	_markers = Node3D.new()
	_markers.name = "Markers"
	add_child(_markers)
	_marker_pool.clear()
	_marker_pool_used = 0
	_marker_sid_slot.clear()
	# Pre-warm marker pool (after mesh exists) to avoid creation hitch on state changes.
	for _i in range(128):
		var node := MeshInstance3D.new()
		node.mesh = _marker_box_mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visible = false
		node.material_override = StandardMaterial3D.new()
		(node.material_override as StandardMaterial3D).emission_enabled = true
		_markers.add_child(node)
		_marker_pool.append(node)
	_soldiers = Node3D.new()
	_soldiers.name = "Soldiers"
	add_child(_soldiers)
	_soldier_pool.clear()
	_soldier_pool_used = 0
	_bombers = Node3D.new()
	_bombers.name = "Bombers"
	add_child(_bombers)
	_bomber_pool.clear()
	_bomber_pool_used = 0
	_bomb_drop_mesh = SphereMesh.new()
	_bomb_drop_mesh.radius = 0.22
	_bomb_drop_mesh.height = 0.44
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
	_setup_road_multimeshes()
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
	_resource_link_material = StandardMaterial3D.new()
	_resource_link_material.albedo_color = Color(0.72, 0.68, 0.38, 0.85)
	_resource_link_material.emission_enabled = true
	_resource_link_material.emission = Color(0.55, 0.5, 0.2)
	_resource_link_material.emission_energy_multiplier = 0.6
	_resource_link_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_resource_link_material.no_depth_test = false
	_resource_link_material.render_priority = RESOURCE_RENDER_PRIORITY
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
		lmat.no_depth_test = false
		lmat.render_priority = RESOURCE_RENDER_PRIORITY
		_resource_link_materials.append(lmat)
		var lmat_dim := StandardMaterial3D.new()
		lmat_dim.albedo_color = Color(col.r, col.g, col.b, 0.36)
		lmat_dim.emission_enabled = true
		lmat_dim.emission = col * 0.2
		lmat_dim.emission_energy_multiplier = 0.45
		lmat_dim.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lmat_dim.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lmat_dim.no_depth_test = false
		lmat_dim.render_priority = RESOURCE_RENDER_PRIORITY
		_resource_link_materials_linking.append(lmat_dim)
	_road_cache_land.clear()
	_road_cache_bridge.clear()
	_road_cached_seg_total.clear()
	_network_built_cells.clear()
	_network_road_land.clear()
	_network_road_bridge.clear()
	_path_cache.clear()
	_reset_road_multimesh_instances()
	_resource_link_seg_count.clear()
	_resource_link_nodes.clear()
	_pulse_pool.clear()
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


## B8/H5: effective mesh dimensions after detail scale (min 36×18 quads).
func effective_globe_mesh_dims() -> Vector2i:
	var s: float = clampf(_mesh_detail_scale, 0.35, 1.0)
	return Vector2i(
		maxi(int(round(float(WorldConquestConfigLib.GLOBE_MESH_W) * s)), 36),
		maxi(int(round(float(WorldConquestConfigLib.GLOBE_MESH_H) * s)), 18),
	)


func effective_fluid_mesh_dims() -> Vector2i:
	var s: float = clampf(_mesh_detail_scale, 0.35, 1.0)
	return Vector2i(
		maxi(int(round(float(WorldConquestConfigLib.FLUID_MESH_W) * s)), 36),
		maxi(int(round(float(WorldConquestConfigLib.FLUID_MESH_H) * s)), 18),
	)


## B8/H5: quality knobs (config + runtime detail). Screen applies GLOBE_RENDER_SCALE to SubViewport.
func get_globe_render_knobs() -> Dictionary:
	var g: Vector2i = effective_globe_mesh_dims()
	var f: Vector2i = effective_fluid_mesh_dims()
	return {
		"globe_mesh_w": g.x,
		"globe_mesh_h": g.y,
		"fluid_mesh_w": f.x,
		"fluid_mesh_h": f.y,
		"mesh_detail_scale": clampf(_mesh_detail_scale, 0.35, 1.0),
		"globe_render_scale": WorldConquestConfigLib.GLOBE_RENDER_SCALE,
		"road_mm_min_capacity": _ROAD_MM_MIN_CAPACITY,
		"overlay_owners_only": WorldConquestConfigLib.OVERLAY_OWNERS_ONLY,
	}


## Optional lower-detail path. Call before setup() or re-setup to rebuild meshes.
func set_mesh_detail_scale(scale: float) -> void:
	_mesh_detail_scale = clampf(scale, 0.35, 1.0)


func _build_globe_mesh_for_detail(fluid: bool) -> ArrayMesh:
	# Full detail uses public builders (config GLOBE_MESH_*/FLUID_MESH_*).
	# Lower detail scales those knobs and calls the mesh builder with explicit dims (B8/H5).
	var s: float = clampf(_mesh_detail_scale, 0.35, 1.0)
	if s >= 0.999:
		if fluid:
			return EarthGlobeMeshLib.build_fluid_globe(battle_data, _world_map_id)
		return EarthGlobeMeshLib.build_globe(battle_data, _world_map_id)
	var dims: Vector2i = effective_fluid_mesh_dims() if fluid else effective_globe_mesh_dims()
	return EarthGlobeMeshLib._build_globe_mesh(
		battle_data, fluid, dims.x, dims.y, _world_map_id
	)


func _apply_terrain_material() -> void:
	if _globe_mi == null or battle_data == null:
		return
	var albedo_img: Image = PlanetVisualBakeLib.build_albedo_image(battle_data, _world_map_id)
	var height_img: Image = PlanetVisualBakeLib.build_height_image(battle_data)
	if albedo_img == null or height_img == null:
		var fallback := StandardMaterial3D.new()
		fallback.vertex_color_use_as_albedo = true
		fallback.roughness = 0.9
		fallback.cull_mode = BaseMaterial3D.CULL_BACK
		_globe_mi.material_override = fallback
		return
	_albedo_tex = ImageTexture.create_from_image(albedo_img)
	_height_tex = ImageTexture.create_from_image(height_img)
	_terrain_shader_mat = ShaderMaterial.new()
	_terrain_shader_mat.shader = _TERRAIN_SHADER
	_terrain_shader_mat.set_shader_parameter("albedo_map", _albedo_tex)
	_terrain_shader_mat.set_shader_parameter("height_map", _height_tex)
	_terrain_shader_mat.set_shader_parameter(
		"height_scale", WorldConquestConfigLib.HEIGHT_SCALE
	)
	_terrain_shader_mat.set_shader_parameter("ambient_boost", 0.22)
	_globe_mi.material_override = _terrain_shader_mat


func _add_atmosphere_shell() -> void:
	_atmosphere_mi = MeshInstance3D.new()
	_atmosphere_mi.name = "Atmosphere"
	var sm := SphereMesh.new()
	var r: float = (
		WorldConquestConfigLib.GLOBE_RADIUS * WorldConquestConfigLib.ATMOSPHERE_RADIUS_SCALE
	)
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 64
	sm.rings = 32
	_atmosphere_mi.mesh = sm
	_atmosphere_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var amat := ShaderMaterial.new()
	amat.shader = _ATMOSPHERE_SHADER
	var atmo_col: Color = WorldConquestMapGeneratorLib.globe_colors_for_map(_world_map_id).get(
		"ocean", Color(0.05, 0.18, 0.42)
	)
	amat.set_shader_parameter(
		"atmosphere_color",
		Vector3(
			clampf(atmo_col.r * 1.6 + 0.15, 0.0, 1.0),
			clampf(atmo_col.g * 1.4 + 0.25, 0.0, 1.0),
			clampf(atmo_col.b * 1.2 + 0.35, 0.0, 1.0),
		),
	)
	amat.set_shader_parameter("intensity", 0.4)
	amat.set_shader_parameter("power", 2.4)
	_atmosphere_mi.material_override = amat
	add_child(_atmosphere_mi)


## True when surface point faces the camera (front hemisphere). Hides far-side ghosts.
func _is_front_hemisphere(world_pos: Vector3) -> bool:
	if camera == null:
		return true
	if world_pos.length_squared() < 0.0001:
		return true
	var outward: Vector3 = world_pos.normalized()
	var to_cam: Vector3 = camera.global_position - world_pos
	if to_cam.length_squared() < 0.0001:
		return true
	return outward.dot(to_cam.normalized()) > 0.02


## H4: Slow full-grid fluid bake — live WC prefers ownership R8/delta from Screen drain only.
## Do not call every sim step under WorldDataset live; use apply_ownership_display_* instead.
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


static func owner_display_byte_for(owner: int) -> int:
	return _owner_display_byte(owner)


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


func get_owner_cache_byte(idx: int) -> int:
	if idx < 0 or idx >= _owner_bytes_cache.size():
		return 0
	return int(_owner_bytes_cache[idx])


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
	# H4 / I2 / I3 — SLOW full-grid GDScript owner→R8 map (65k loop). Forbidden on live hot path.
	# Live WC Screen apply path must use:
	#   apply_ownership_display_bytes (pre-baked R8) or apply_ownership_display_delta (indices+R8).
	# Fallback only: CPU backend, load recovery, non-live tools. Prefer R8 from Rust authority.
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
	_owner_bytes_cache = bytes
	_border_bytes_cache.resize(n)
	_rebuild_border_mask_full()
	_owner_overlay_patch_frame = -1
	_upload_owner_gpu_textures(true)


## Incremental overlay patch with pre-mapped R8 bytes from Rust (WorldDataset display buffer).
func apply_ownership_display_delta(
	indices: PackedInt32Array, r8_values: PackedByteArray
) -> void:
	if not _gpu_ownership_ready or battle_data == null or _owner_img_gpu == null:
		return
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	var n: int = mini(indices.size(), r8_values.size())
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
		_owner_bytes_cache[idx] = r8_values[i]
	if n > 256:
		_rebuild_border_mask_full()
	else:
		_update_border_mask_for_indices(indices)
	_owner_overlay_patch_frame = Engine.get_process_frames()
	_upload_owner_gpu_textures()


func apply_ownership_overlay_delta(
	indices: PackedInt32Array, values: PackedByteArray
) -> void:
	## H4: CPU-backend / legacy delta — owner enum bytes mapped to display R8 here.
	## Live WC prefers apply_ownership_display_delta (pre-mapped R8 from PresentationTxn).
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
				elif kind == WorldConquestOutpostBuildLib.KIND_HANGAR:
					col = Color(0.35, 0.38, 0.55).lerp(Color(0.55, 0.62, 0.95), prog)
				else:
					col = Color(0.3, 0.45, 0.62).lerp(Color(0.25, 0.65, 1.0), prog)
				scale_f = lerpf(0.78, 1.0, prog)
				alpha = lerpf(0.65, 1.0, prog)
			_:
				# Completed land bridge (ACTIVE corridor still in placed_structures briefly).
				if kind == WorldConquestOutpostBuildLib.KIND_CORRIDOR_LINK:
					col = Color(0.28, 0.88, 0.78) if team == 1 else Color(0.95, 0.55, 0.42)
				elif kind == WorldConquestOutpostBuildLib.KIND_BARRACKS:
					col = Color(0.82, 0.58, 0.24) if team == 1 else Color(0.9, 0.45, 0.28)
				elif kind == WorldConquestOutpostBuildLib.KIND_HANGAR:
					col = Color(0.52, 0.68, 0.98) if team == 1 else Color(0.95, 0.48, 0.38)
				else:
					col = Color(0.25, 0.65, 1.0) if team == 1 else Color(1.0, 0.4, 0.3)
		if hp_frac < 1.0:
			col = col.lerp(Color(0.92, 0.28, 0.18), 1.0 - hp_frac)
			scale_f *= lerpf(0.85, 1.0, hp_frac)
		var sid: int = int(st.get("id", -1))
		if sid >= 0:
			_marker_sid_slot[sid] = _marker_pool_used
		_place_pooled_marker(Vector2i(gx, gy), col, scale_f, alpha)
	# Completed land bridges live in bridge_corridors (not placed_structures) — solid pin at landing.
	if battle_data != null:
		for corridor: Dictionary in battle_data.bridge_corridors:
			var cgx: int = int(corridor.get("gx", -1))
			var cgy: int = int(corridor.get("gy", -1))
			if cgx < 0:
				continue
			var cteam: int = int(corridor.get("team", 1))
			var ccol: Color = (
				Color(0.28, 0.88, 0.78) if cteam == 1 else Color(0.95, 0.55, 0.42)
			)
			var csid: int = int(corridor.get("id", -1))
			if csid >= 0:
				_marker_sid_slot[csid] = _marker_pool_used
			_place_pooled_marker(Vector2i(cgx, cgy), ccol, 1.05, 1.0)
	for i in range(_marker_pool_used, _marker_pool.size()):
		_marker_pool[i].visible = false


func refresh_connecting_markers(structures: Array, home_player: Vector2i, home_enemy: Vector2i) -> void:
	if _markers == null:
		return
	if _marker_sid_slot.is_empty():
		refresh_markers(structures, home_player, home_enemy)
		return
	# H1/H3/I10: Only CONNECTING (road still growing) blinks.
	# BUILDING / ACTIVE / path-complete must not pulse — authority state is source of truth.
	# Path-complete / state txn paths call refresh_markers([sid]) to freeze solid colors.
	var pulse_sids: Array[int] = []
	for st: Dictionary in structures:
		if not WorldConquestOutpostBuildLib.is_corridor_path_kind(str(st.get("kind", ""))):
			continue
		var state: String = str(st.get("state", WorldConquestOutpostBuildLib.STATE_ACTIVE))
		if state != WorldConquestOutpostBuildLib.STATE_CONNECTING:
			continue
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
	# I10: pulse scale/alpha only for CONNECTING. BUILDING/ACTIVE use solid colors.
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
			elif kind == WorldConquestOutpostBuildLib.KIND_HANGAR:
				col = Color(0.35, 0.38, 0.55).lerp(Color(0.55, 0.62, 0.95), prog)
			else:
				col = Color(0.3, 0.45, 0.62).lerp(Color(0.25, 0.65, 1.0), prog)
			scale_f = lerpf(0.78, 1.0, prog)
			alpha = lerpf(0.65, 1.0, prog)
		_:
			if kind == WorldConquestOutpostBuildLib.KIND_CORRIDOR_LINK:
				col = Color(0.28, 0.88, 0.78) if team == 1 else Color(0.95, 0.55, 0.42)
			elif kind == WorldConquestOutpostBuildLib.KIND_BARRACKS:
				col = Color(0.82, 0.58, 0.24) if team == 1 else Color(0.9, 0.45, 0.28)
			elif kind == WorldConquestOutpostBuildLib.KIND_HANGAR:
				col = Color(0.52, 0.68, 0.98) if team == 1 else Color(0.95, 0.48, 0.38)
			else:
				col = Color(0.25, 0.65, 1.0) if team == 1 else Color(1.0, 0.4, 0.3)
	if hp_frac < 1.0:
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
		_place_pooled_soldier(grid, int(teams[i]))
	for j in range(_soldier_pool_used, _soldier_pool.size()):
		_soldier_pool[j].visible = false


func _unit_sprite_texture(is_bomber: bool, team: int) -> Texture2D:
	var friendly: bool = team == BattleTileControlLib.OWNER_FRIENDLY
	if is_bomber:
		return TEX_BOMBER_FRIENDLY if friendly else TEX_BOMBER_HOSTILE
	return TEX_SOLDIER_FRIENDLY if friendly else TEX_SOLDIER_HOSTILE


func _make_unit_billboard(is_bomber: bool) -> Sprite3D:
	var node := Sprite3D.new()
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.shaded = false
	node.double_sided = true
	node.transparent = true
	node.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	node.alpha_scissor_threshold = 0.15
	node.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	node.pixel_size = BOMBER_SPRITE_PIXEL_SIZE if is_bomber else SOLDIER_SPRITE_PIXEL_SIZE
	node.render_priority = UNIT_RENDER_PRIORITY
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.centered = true
	node.no_depth_test = false
	node.visible = false
	return node


func _place_pooled_soldier(grid: Vector2i, team: int) -> void:
	if _soldiers == null or battle_data == null or grid.x < 0:
		return
	while _soldier_pool.size() <= _soldier_pool_used:
		var node: Sprite3D = _make_unit_billboard(false)
		_soldiers.add_child(node)
		_soldier_pool.append(node)
	var sprite: Sprite3D = _soldier_pool[_soldier_pool_used]
	_soldier_pool_used += 1
	sprite.visible = true
	sprite.texture = _unit_sprite_texture(false, team)
	sprite.position = _grid_surface_pos(grid, SOLDIER_SURFACE_LIFT)
	sprite.scale = Vector3.ONE
	sprite.visible = _is_front_hemisphere(sprite.position)


func sync_bombers(
	teams: PackedByteArray,
	gx: PackedInt32Array,
	gy: PackedInt32Array,
	search_scope: PackedInt32Array = PackedInt32Array(),
) -> void:
	if _bombers == null:
		return
	_bomber_pool_used = 0
	var n: int = mini(teams.size(), mini(gx.size(), gy.size()))
	for i in range(n):
		var grid := Vector2i(gx[i], gy[i])
		if grid.x < 0:
			continue
		var scope: int = int(search_scope[i]) if i < search_scope.size() else 0
		_place_pooled_bomber(grid, int(teams[i]), scope)
	for j in range(_bomber_pool_used, _bomber_pool.size()):
		_bomber_pool[j].visible = false


func _bomber_scope_visual_scale(scope: int) -> float:
	var initial: int = WorldConquestConfigLib.BOMBER_SEARCH_EXPAND_INITIAL
	var max_scope: int = WorldConquestConfigLib.BOMBER_SEARCH_EXPAND_MAX
	if scope <= 0:
		scope = initial
	if max_scope <= initial:
		return 1.0
	var t: float = clampf(
		float(scope - initial) / float(max_scope - initial),
		0.0,
		1.0,
	)
	return lerpf(1.0, 1.85, t)


func _place_pooled_bomber(grid: Vector2i, team: int, search_scope: int = 0) -> void:
	if _bombers == null or battle_data == null or grid.x < 0:
		return
	while _bomber_pool.size() <= _bomber_pool_used:
		var node: Sprite3D = _make_unit_billboard(true)
		_bombers.add_child(node)
		_bomber_pool.append(node)
	var sprite: Sprite3D = _bomber_pool[_bomber_pool_used]
	_bomber_pool_used += 1
	sprite.visible = true
	sprite.texture = _unit_sprite_texture(true, team)
	var scope_scale: float = _bomber_scope_visual_scale(search_scope)
	sprite.scale = Vector3(scope_scale, scope_scale, scope_scale)
	sprite.position = _grid_surface_pos(grid, WorldConquestConfigLib.BOMBER_SURFACE_LIFT)
	sprite.visible = _is_front_hemisphere(sprite.position)


func play_bomb_drops(teams: PackedByteArray, gx: PackedInt32Array, gy: PackedInt32Array) -> void:
	if _effects == null or battle_data == null:
		return
	var n: int = mini(teams.size(), mini(gx.size(), gy.size()))
	for i in range(n):
		_spawn_bomb_drop(Vector2i(gx[i], gy[i]), int(teams[i]))


func _spawn_bomb_drop(grid: Vector2i, team: int) -> void:
	if grid.x < 0:
		return
	var col: Color = Color(1.0, 0.55, 0.15) if team == 1 else Color(1.0, 0.28, 0.18)
	var top: Vector3 = _grid_surface_pos(grid, WorldConquestConfigLib.BOMBER_SURFACE_LIFT)
	var ground: Vector3 = _grid_surface_pos(grid, 0.55)
	var bomb := MeshInstance3D.new()
	bomb.mesh = _bomb_drop_mesh
	bomb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col * 0.9
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bomb.material_override = mat
	bomb.position = top
	_effects.add_child(bomb)
	var tween := create_tween()
	tween.tween_property(bomb, "position", ground, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		_spawn_bomb_impact_fx(ground, col)
		bomb.queue_free()
	)


func _spawn_bomb_impact_fx(pos: Vector3, col: Color) -> void:
	if _effects == null:
		return
	var flash := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.55
	mesh.height = 1.1
	flash.mesh = mesh
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash.material_override = mat
	flash.position = pos
	_effects.add_child(flash)
	var tween := create_tween()
	tween.tween_property(flash, "scale", Vector3(2.2, 2.2, 2.2), 0.35)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tween.tween_callback(flash.queue_free)


## B4: `changed_sids` non-empty → only those sids get path-cache growth/append.
## Full MultiMesh rewrite from caches happens only on shrink/remove/capacity-grow,
## never by re-walking every structure when an incremental sid list is provided.
## Empty `changed_sids` = full structure pass (load/reset). Prefer always pass dirty sids live.
func sync_roads(structures: Array, changed_sids: Array = [], network_roads: bool = false) -> void:
	if _roads == null or battle_data == null:
		return
	var incremental: bool = not changed_sids.is_empty()
	var changed_set: Dictionary = {}
	if incremental:
		for sid_v in changed_sids:
			changed_set[int(sid_v)] = true
	var live_ids: Dictionary = {}
	var need_full_rebuild: bool = false
	for st: Dictionary in structures:
		if not WorldConquestOutpostBuildLib.is_corridor_path_kind(str(st.get("kind", ""))):
			continue
		# Logistics network MultiMesh owns progressive roads for spawners/barracks/hangars.
		# Drawing structure path_built too doubles cost every cell during CONNECTING.
		var kind: String = str(st.get("kind", ""))
		if network_roads and kind != WorldConquestOutpostBuildLib.KIND_CORRIDOR_LINK:
			continue
		var sid: int = int(st.get("id", -1))
		if sid < 0:
			continue
		live_ids[sid] = true
		if not incremental or changed_set.has(sid):
			# Growth is O(delta) append; shrink returns need_rebuild (B4).
			if _sync_outpost_road(st, sid, false):
				need_full_rebuild = true
	for corridor: Dictionary in battle_data.bridge_corridors:
		var sid: int = int(corridor.get("id", -1))
		if sid < 0:
			continue
		live_ids[sid] = true
		if not incremental or changed_set.has(sid):
			var pseudo: Dictionary = corridor.duplicate()
			pseudo["state"] = WorldConquestOutpostBuildLib.STATE_ACTIVE
			if _sync_outpost_road(pseudo, sid, false):
				need_full_rebuild = true
	# Orphan cleanup (O(cached sids), not O(path cells)). Remove/reset triggers MultiMesh
	# reseed from remaining caches — not a per-sid path rewalk of live growth sids (B4).
	for sid in _road_cached_seg_total.keys():
		if not live_ids.has(sid):
			if _clear_road(sid, false):
				need_full_rebuild = true
	if need_full_rebuild:
		_rebuild_road_multimesh_from_caches()


#region Road MultiMesh (B3/I4/H2 — helpers in EarthGlobeRoads.gd)

func _setup_road_multimeshes() -> void:
	if _roads == null or _shared_road_box == null:
		return
	if _road_land_mm != null and is_instance_valid(_road_land_mm):
		_road_land_mm.queue_free()
	if _road_bridge_mm != null and is_instance_valid(_road_bridge_mm):
		_road_bridge_mm.queue_free()
	_road_land_mm = MultiMeshInstance3D.new()
	_road_land_mm.name = "RoadLandMM"
	var land_mm := MultiMesh.new()
	land_mm.transform_format = MultiMesh.TRANSFORM_3D
	land_mm.mesh = _shared_road_box
	# Preallocate large capacity once — raising instance_count mid-run wipes buffers (I4).
	land_mm.instance_count = _ROAD_MM_MIN_CAPACITY
	land_mm.visible_instance_count = 0
	_road_land_mm.multimesh = land_mm
	_road_land_mm.material_override = _road_material
	_road_land_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_road_land_mm.sorting_offset = 2.0
	_roads.add_child(_road_land_mm)
	_road_bridge_mm = MultiMeshInstance3D.new()
	_road_bridge_mm.name = "RoadBridgeMM"
	var bridge_mm := MultiMesh.new()
	bridge_mm.transform_format = MultiMesh.TRANSFORM_3D
	bridge_mm.mesh = _shared_road_box
	bridge_mm.instance_count = _ROAD_MM_MIN_CAPACITY
	bridge_mm.visible_instance_count = 0
	_road_bridge_mm.multimesh = bridge_mm
	_road_bridge_mm.material_override = _bridge_material
	_road_bridge_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_road_bridge_mm.sorting_offset = 2.0
	_roads.add_child(_road_bridge_mm)
	_road_mm_land_used = 0
	_road_mm_bridge_used = 0


func _collect_road_multimesh_xforms() -> Array:
	## Authoritative transform lists for full reseed after capacity grow / remove.
	var land_xforms: Array[Transform3D] = []
	for xform_var in _network_road_land:
		land_xforms.append(xform_var)
	for sid in _road_cache_land.keys():
		for xform_var in _road_cache_land[sid]:
			land_xforms.append(xform_var)
	var bridge_xforms: Array[Transform3D] = []
	for xform_var in _network_road_bridge:
		bridge_xforms.append(xform_var)
	for sid in _road_cache_bridge.keys():
		for xform_var in _road_cache_bridge[sid]:
			bridge_xforms.append(xform_var)
	return [land_xforms, bridge_xforms]


## Full rewrite from authoritative caches (remove/reset, or capacity growth — H2/I4).
func _rebuild_road_multimesh_from_caches() -> void:
	if _road_land_mm == null or _road_bridge_mm == null:
		return
	var pair: Array = _collect_road_multimesh_xforms()
	_write_multimesh_transforms(_road_land_mm, pair[0], true)
	_write_multimesh_transforms(_road_bridge_mm, pair[1], false)


func _reset_road_multimesh_instances() -> void:
	_road_mm_land_used = 0
	_road_mm_bridge_used = 0
	if _road_land_mm != null and _road_land_mm.multimesh != null:
		_road_land_mm.multimesh.visible_instance_count = 0
	if _road_bridge_mm != null and _road_bridge_mm.multimesh != null:
		_road_bridge_mm.multimesh.visible_instance_count = 0


## Append new segments. Does NOT raise instance_count (that would wipe prior instances).
## If capacity is exceeded, rebuilds from caches with a larger buffer (grow+reseed).
func _append_road_multimesh_transforms(
	land_new: Array[Transform3D], bridge_new: Array[Transform3D]
) -> void:
	if land_new.is_empty() and bridge_new.is_empty():
		return
	if not _try_append_multimesh(_road_land_mm, land_new, true):
		_rebuild_road_multimesh_from_caches()
		return
	if not _try_append_multimesh(_road_bridge_mm, bridge_new, false):
		_rebuild_road_multimesh_from_caches()


func clear_network_roads() -> void:
	_network_built_cells.clear()
	_network_road_land.clear()
	_network_road_bridge.clear()
	_rebuild_road_multimesh_from_caches()


func apply_network_road_cells(cells: PackedInt32Array) -> void:
	if battle_data == null or cells.is_empty():
		return
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	var land_new: Array[Transform3D] = []
	var bridge_new: Array[Transform3D] = []
	const DIRS: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	for i in range(cells.size()):
		var key: int = cells[i]
		if key < 0 or _network_built_cells.has(key):
			continue
		_network_built_cells[key] = true
		var gx: int = key % w
		var gy: int = key / w
		var b: Vector2i = Vector2i(gx, gy)
		for d: Vector2i in DIRS:
			var nx: int = gx + d.x
			var ny: int = gy + d.y
			if ny < 0 or ny >= h:
				continue
			if nx < 0:
				nx = w - 1
			elif nx >= w:
				nx = 0
			var nk: int = ny * w + nx
			if not _network_built_cells.has(nk):
				continue
			var a: Vector2i = Vector2i(nx, ny)
			var xform: Transform3D = _road_segment_transform(a, b)
			if _segment_is_bridge(a, b):
				_network_road_bridge.append(xform)
				bridge_new.append(xform)
			else:
				_network_road_land.append(xform)
				land_new.append(xform)
			break
	if not land_new.is_empty() or not bridge_new.is_empty():
		_append_road_multimesh_transforms(land_new, bridge_new)


func _write_multimesh_transforms(mm_node: MultiMeshInstance3D, xforms: Array, is_land: bool) -> void:
	if mm_node == null or mm_node.multimesh == null:
		return
	# B3/I4/H2: EarthGlobeRoads.write_all_transforms grows capacity then reseeds ALL
	# transforms from the provided list — never leave wiped slots after instance_count change.
	var n: int = EarthGlobeRoadsLib.write_all_transforms(
		mm_node.multimesh, xforms, _ROAD_MM_MIN_CAPACITY
	)
	if is_land:
		_road_mm_land_used = n
	else:
		_road_mm_bridge_used = n


## Returns false if capacity is insufficient (caller must rebuild from caches).
func _try_append_multimesh(mm_node: MultiMeshInstance3D, xforms: Array, is_land: bool) -> bool:
	if mm_node == null or mm_node.multimesh == null:
		return true
	if xforms.is_empty():
		return true
	var used: int = _road_mm_land_used if is_land else _road_mm_bridge_used
	# Never raise instance_count here — append-only; -1 means need full reseed grow path.
	var new_used: int = EarthGlobeRoadsLib.try_append_transforms(mm_node.multimesh, used, xforms)
	if new_used < 0:
		return false
	if is_land:
		_road_mm_land_used = new_used
	else:
		_road_mm_bridge_used = new_used
	return true


func road_multimesh_used_counts() -> Dictionary:
	return {
		"land_used": _road_mm_land_used,
		"bridge_used": _road_mm_bridge_used,
		"land_visible": (
			_road_land_mm.multimesh.visible_instance_count
			if _road_land_mm != null and _road_land_mm.multimesh != null
			else 0
		),
		"bridge_visible": (
			_road_bridge_mm.multimesh.visible_instance_count
			if _road_bridge_mm != null and _road_bridge_mm.multimesh != null
			else 0
		),
		"land_capacity": (
			_road_land_mm.multimesh.instance_count
			if _road_land_mm != null and _road_land_mm.multimesh != null
			else 0
		),
		"bridge_capacity": (
			_road_bridge_mm.multimesh.instance_count
			if _road_bridge_mm != null and _road_bridge_mm.multimesh != null
			else 0
		),
		"network_land": _network_road_land.size(),
		"network_bridge": _network_road_bridge.size(),
	}


## Unit exercise of the shipped MultiMesh append path + capacity-grow reseed (B3/I4).
## Appends `batches` × `per_batch` synthetic land segments; asserts cumulative visible count.
## When force_grow is true, capacity is collapsed so append must rebuild-from-buffer.
func selfcheck_road_multimesh_append(
	batches: int = 5, per_batch: int = 4, force_grow: bool = true
) -> Dictionary:
	if _shared_road_box == null:
		_shared_road_box = BoxMesh.new()
		_shared_road_box.size = Vector3.ONE
	if _roads == null or not is_instance_valid(_roads):
		_roads = Node3D.new()
		_roads.name = "RoadsSelfcheck"
		add_child(_roads)
	if _road_material == null:
		_road_material = StandardMaterial3D.new()
		_road_material.albedo_color = ROAD_COLOR
		_road_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if _bridge_material == null:
		_bridge_material = StandardMaterial3D.new()
		_bridge_material.albedo_color = BRIDGE_COLOR
		_bridge_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if _road_land_mm == null or _road_land_mm.multimesh == null:
		_setup_road_multimeshes()
	if _road_land_mm == null or _road_land_mm.multimesh == null:
		return {"ok": false, "error": "road multimesh not available"}
	_network_road_land.clear()
	_network_road_bridge.clear()
	_road_cache_land.clear()
	_road_cache_bridge.clear()
	_road_cached_seg_total.clear()
	_road_mm_land_used = 0
	_road_mm_bridge_used = 0
	# Collapse capacity so the first overflow exercises grow+reseed from caches (I4).
	# Setting instance_count wipes buffers — visible stays 0 until we write transforms.
	if force_grow:
		_road_land_mm.multimesh.instance_count = maxi(per_batch, 1)
	elif _road_land_mm.multimesh.instance_count < _ROAD_MM_MIN_CAPACITY:
		_road_land_mm.multimesh.instance_count = _ROAD_MM_MIN_CAPACITY
	_road_land_mm.multimesh.visible_instance_count = 0
	if _road_bridge_mm != null and _road_bridge_mm.multimesh != null:
		if force_grow:
			_road_bridge_mm.multimesh.instance_count = maxi(per_batch, 1)
		elif _road_bridge_mm.multimesh.instance_count < _ROAD_MM_MIN_CAPACITY:
			_road_bridge_mm.multimesh.instance_count = _ROAD_MM_MIN_CAPACITY
		_road_bridge_mm.multimesh.visible_instance_count = 0
	var expected: int = 0
	var grew: bool = false
	var cap_before_grow: int = _road_land_mm.multimesh.instance_count
	for _b in range(maxi(batches, 1)):
		var land_new: Array[Transform3D] = []
		for _i in range(maxi(per_batch, 1)):
			var t := Transform3D(Basis.IDENTITY, Vector3(float(expected + _i), 0.0, 0.0))
			land_new.append(t)
			_network_road_land.append(t)
		var cap_before: int = _road_land_mm.multimesh.instance_count
		_append_road_multimesh_transforms(land_new, [] as Array[Transform3D])
		if _road_land_mm.multimesh.instance_count > cap_before:
			grew = true
		expected += land_new.size()
		var used_now: int = _road_mm_land_used
		var vis_now: int = _road_land_mm.multimesh.visible_instance_count
		if used_now != expected or vis_now != expected:
			return {
				"ok": false,
				"error": "after batch cumulative mismatch",
				"expected": expected,
				"used": used_now,
				"visible": vis_now,
				"capacity": _road_land_mm.multimesh.instance_count,
			}
	var counts: Dictionary = road_multimesh_used_counts()
	var ok: bool = (
		int(counts.get("land_used", 0)) == expected
		and int(counts.get("land_visible", 0)) == expected
	)
	if force_grow and expected > cap_before_grow and not grew:
		ok = false
		counts["error"] = "expected capacity grow reseed but capacity did not increase"
	counts["ok"] = ok
	counts["expected"] = expected
	counts["grew"] = grew
	counts["cap_before_grow"] = cap_before_grow
	return counts

#endregion


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


## Returns true only when a full MultiMesh rebuild is required (shrink/remove).
## Path growth is append-only and returns false after applying O(delta) updates.
func _sync_outpost_road(st: Dictionary, sid: int, flush_now: bool = true) -> bool:
	var packed: PackedInt32Array = _packed_path_keys(st, sid)
	if packed.is_empty():
		return false
	var w: int = battle_data.grid_width
	var state: String = str(st.get("state", WorldConquestOutpostBuildLib.STATE_ACTIVE))
	var built_cells: int
	if state == WorldConquestOutpostBuildLib.STATE_CONNECTING:
		built_cells = int(floor(float(st.get("path_built", 1.0))))
	else:
		built_cells = packed.size()
	built_cells = clampi(built_cells, 1, packed.size())
	var need_segs: int = maxi(built_cells - 1, 0)
	var had_cache: bool = _road_cached_seg_total.has(sid)
	var prev_segs: int = int(_road_cached_seg_total.get(sid, 0))
	if had_cache and prev_segs == need_segs:
		return false

	# Shrink or first-time reclass after material change: rewrite sid cache + full rebuild.
	if had_cache and need_segs < prev_segs:
		_road_cached_seg_total[sid] = need_segs
		_replace_outpost_road_cache(sid, packed, need_segs, w)
		if flush_now:
			_rebuild_road_multimesh_from_caches()
		return true

	# Growth or first paint: append only the new segments (O(delta)).
	var from_seg: int = prev_segs if had_cache else 0
	var land_new: Array[Transform3D] = []
	var bridge_new: Array[Transform3D] = []
	for i in range(from_seg, need_segs):
		var a: Vector2i = WorldConquestOutpostBuildLib.grid_from_packed_key(packed[i], w)
		var b: Vector2i = WorldConquestOutpostBuildLib.grid_from_packed_key(packed[i + 1], w)
		var xform: Transform3D = _road_segment_transform(a, b)
		if _segment_is_bridge(a, b):
			bridge_new.append(xform)
		else:
			land_new.append(xform)
	_road_cached_seg_total[sid] = need_segs
	if not land_new.is_empty():
		if not _road_cache_land.has(sid):
			_road_cache_land[sid] = [] as Array[Transform3D]
		var land_cache: Array = _road_cache_land[sid]
		for xform_var in land_new:
			land_cache.append(xform_var)
		_road_cache_land[sid] = land_cache
	if not bridge_new.is_empty():
		if not _road_cache_bridge.has(sid):
			_road_cache_bridge[sid] = [] as Array[Transform3D]
		var bridge_cache: Array = _road_cache_bridge[sid]
		for xform_var2 in bridge_new:
			bridge_cache.append(xform_var2)
		_road_cache_bridge[sid] = bridge_cache
	_append_road_multimesh_transforms(land_new, bridge_new)
	return false


func _replace_outpost_road_cache(sid: int, packed: PackedInt32Array, need_segs: int, w: int) -> void:
	var land_xforms: Array[Transform3D] = []
	var bridge_xforms: Array[Transform3D] = []
	for i in range(need_segs):
		var a: Vector2i = WorldConquestOutpostBuildLib.grid_from_packed_key(packed[i], w)
		var b: Vector2i = WorldConquestOutpostBuildLib.grid_from_packed_key(packed[i + 1], w)
		var xform: Transform3D = _road_segment_transform(a, b)
		if _segment_is_bridge(a, b):
			bridge_xforms.append(xform)
		else:
			land_xforms.append(xform)
	if land_xforms.is_empty():
		_road_cache_land.erase(sid)
	else:
		_road_cache_land[sid] = land_xforms
	if bridge_xforms.is_empty():
		_road_cache_bridge.erase(sid)
	else:
		_road_cache_bridge[sid] = bridge_xforms


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


func _clear_road(sid: int, flush_now: bool = true) -> bool:
	var had: bool = (
		_road_cache_land.has(sid)
		or _road_cache_bridge.has(sid)
		or _road_cached_seg_total.has(sid)
		or _path_cache.has(sid)
	)
	_road_cache_land.erase(sid)
	_road_cache_bridge.erase(sid)
	_road_cached_seg_total.erase(sid)
	_path_cache.erase(sid)
	if had and flush_now:
		_rebuild_road_multimesh_from_caches()
	return had


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
	mat.no_depth_test = false
	mat.render_priority = RESOURCE_RENDER_PRIORITY
	cyl.material_override = mat
	cyl.position = pos
	cyl.visible = _is_front_hemisphere(pos)
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
	box.position = _grid_surface_pos(grid, 1.5)
	box.scale = Vector3.ONE * (1.8 * scale_f)
	box.visible = _is_front_hemisphere(box.position)
	var mat := box.material_override as StandardMaterial3D
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.emission = Color(color.r, color.g, color.b) * 0.5
	mat.no_depth_test = false
	mat.render_priority = MARKER_RENDER_PRIORITY
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
	mat.no_depth_test = false
	mat.render_priority = MARKER_RENDER_PRIORITY
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 0.99 else BaseMaterial3D.TRANSPARENCY_DISABLED
	box.material_override = mat
	box.position = pos
	box.visible = _is_front_hemisphere(pos)
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


func _road_segment_transform(a: Vector2i, b: Vector2i) -> Transform3D:
	if battle_data == null or a.x < 0 or b.x < 0:
		return Transform3D.IDENTITY
	var is_bridge: bool = _segment_is_bridge(a, b)
	var pos_a: Vector3 = _link_surface_pos(a)
	var pos_b: Vector3 = _link_surface_pos(b)
	var delta: Vector3 = pos_b - pos_a
	var length: float = delta.length()
	if length < 0.05:
		return Transform3D.IDENTITY
	var y_axis: Vector3 = delta / length
	var x_axis: Vector3 = y_axis.cross(Vector3.UP)
	if x_axis.length_squared() < 0.0001:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	var thickness: float = BRIDGE_THICKNESS if is_bridge else ROAD_THICKNESS
	return Transform3D(
		Basis(x_axis * thickness, y_axis * length, z_axis * thickness),
		(pos_a + pos_b) * 0.5,
	)


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
	_refresh_hemisphere_visibility()


func _refresh_hemisphere_visibility() -> void:
	for i in range(_marker_pool_used):
		var node: MeshInstance3D = _marker_pool[i]
		if node == null:
			continue
		node.visible = _is_front_hemisphere(node.position)
	for i in range(_soldier_pool_used):
		var s: Sprite3D = _soldier_pool[i]
		if s == null:
			continue
		s.visible = _is_front_hemisphere(s.position)
	for i in range(_bomber_pool_used):
		var b: Sprite3D = _bomber_pool[i]
		if b == null:
			continue
		b.visible = _is_front_hemisphere(b.position)
	if _deposits != null:
		for child in _deposits.get_children():
			if child is Node3D:
				(child as Node3D).visible = _is_front_hemisphere((child as Node3D).position)
