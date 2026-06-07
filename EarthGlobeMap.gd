class_name EarthGlobeMap
extends Node3D

const BattleTileFluidFieldLib := preload("res://BattleTileFluidField.gd")
const BattleTerritoryRustBackendLib := preload("res://BattleTerritoryRustBackend.gd")
const WorldConquestConfigLib := preload("res://WorldConquestConfig.gd")
const EarthGlobeMeshLib := preload("res://EarthGlobeMesh.gd")

@onready var camera: Camera3D = $Camera3D

var battle_data = null
var _globe_mi: MeshInstance3D
var _fluid_mi: MeshInstance3D
var _markers: Node3D
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


func refresh_markers(structures: Array, home_player: Vector2i, home_enemy: Vector2i) -> void:
	if _markers == null:
		return
	for c in _markers.get_children():
		c.queue_free()
	_add_capital_marker(home_player, Color(0.2, 0.55, 1.0), 2.2)
	_add_capital_marker(home_enemy, Color(0.95, 0.3, 0.22), 2.2)
	for st: Dictionary in structures:
		var gx: int = int(st.get("gx", 0))
		var gy: int = int(st.get("gy", 0))
		var team: int = int(st.get("team", 1))
		var col: Color = Color(0.25, 0.65, 1.0) if team == 1 else Color(1.0, 0.4, 0.3)
		_add_capital_marker(Vector2i(gx, gy), col, 1.0)


func _add_capital_marker(grid: Vector2i, color: Color, scale_f: float) -> void:
	if battle_data == null or grid.x < 0:
		return
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	var elev: float = battle_data.get_tile_height(grid.x, grid.y) * WorldConquestConfigLib.HEIGHT_SCALE
	var pos: Vector3 = EarthGlobeMeshLib.grid_to_sphere(
		grid.x, grid.y, w, h, WorldConquestConfigLib.GLOBE_RADIUS + elev + 1.5, 0.0
	)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8 * scale_f, 1.8 * scale_f, 1.8 * scale_f)
	box.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.5
	box.material_override = mat
	box.position = pos
	_markers.add_child(box)


func orbit_camera(delta: float, mouse_delta: Vector2) -> void:
	if mouse_delta != Vector2.ZERO:
		_yaw -= mouse_delta.x * WorldConquestConfigLib.CAMERA_ORBIT_SPEED * 0.01
		_pitch = clampf(_pitch - mouse_delta.y * WorldConquestConfigLib.CAMERA_ORBIT_SPEED * 0.01, -0.1, 1.2)
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
