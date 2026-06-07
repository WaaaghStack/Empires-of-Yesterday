class_name WorldRTS3DMap
extends Node3D

const BattleTileFluidFieldLib := preload("res://BattleTileFluidField.gd")
const WorldRTS3DConfigLib := preload("res://WorldRTS3DConfig.gd")
const WorldRTS3DTerrainMeshLib := preload("res://WorldRTS3DTerrainMesh.gd")

@onready var camera: Camera3D = $Camera3D

var battle_data = null
var _terrain_mi: MeshInstance3D
var _fluid_mi: MeshInstance3D
var _markers: Node3D
var _fluid_mat: StandardMaterial3D
var _fluid_tex: ImageTexture
var _camera_height: float = WorldRTS3DConfigLib.CAMERA_DEFAULT_HEIGHT
var _camera_target: Vector3 = Vector3.ZERO


func setup(map_data) -> void:
	battle_data = map_data
	if camera == null:
		camera = get_node_or_null("Camera3D") as Camera3D
	_build_scene()
	_frame_camera()


func _build_scene() -> void:
	for c in get_children():
		if c != camera:
			c.queue_free()
	_terrain_mi = MeshInstance3D.new()
	_terrain_mi.name = "Terrain"
	_terrain_mi.mesh = WorldRTS3DTerrainMeshLib.build(battle_data)
	var tmat := StandardMaterial3D.new()
	tmat.vertex_color_use_as_albedo = true
	tmat.roughness = 0.92
	_terrain_mi.material_override = tmat
	add_child(_terrain_mi)
	_fluid_mi = MeshInstance3D.new()
	_fluid_mi.name = "Fluid"
	_fluid_mi.mesh = WorldRTS3DTerrainMeshLib.build_fluid_drape(battle_data)
	_fluid_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fluid_mi.sorting_offset = 4.0
	_fluid_mi.position.y = 0.0
	var w: int = battle_data.grid_width
	var h: int = battle_data.grid_height
	_fluid_tex = ImageTexture.create_from_image(Image.create(w, h, false, Image.FORMAT_RGBA8))
	_fluid_mat = StandardMaterial3D.new()
	_fluid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fluid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fluid_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fluid_mat.no_depth_test = true
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
	camera.fov = 55.0


func apply_fluid_from_pressures(
	pressure_friendly: PackedFloat32Array,
	pressure_hostile: PackedFloat32Array,
) -> void:
	if battle_data == null or _fluid_tex == null:
		return
	var img: Image = BattleTileFluidFieldLib.build_fluid_image_from_powers(
		battle_data, pressure_friendly, pressure_hostile, 1.0, 0
	)
	if img == null:
		return
	_fluid_tex.update(img)


func refresh_markers(structures: Array, home_player: Vector2i, home_enemy: Vector2i) -> void:
	if _markers == null:
		return
	for c in _markers.get_children():
		c.queue_free()
	_add_marker(home_player, Color(0.2, 0.55, 1.0), 1.2)
	_add_marker(home_enemy, Color(0.95, 0.3, 0.22), 1.2)
	for st: Dictionary in structures:
		var gx: int = int(st.get("gx", 0))
		var gy: int = int(st.get("gy", 0))
		var team: int = int(st.get("team", 1))
		var col: Color = Color(0.25, 0.65, 1.0) if team == 1 else Color(1.0, 0.4, 0.3)
		_add_marker(Vector2i(gx, gy), col, 0.65)


func _add_marker(grid: Vector2i, color: Color, scale_f: float) -> void:
	if battle_data == null or grid.x < 0:
		return
	var c2: Vector2 = battle_data.cell_center(grid.x, grid.y)
	var elev: float = battle_data.get_tile_height(grid.x, grid.y) * WorldRTS3DConfigLib.HEIGHT_SCALE
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(battle_data.cell_size * scale_f, 1.8 * scale_f, battle_data.cell_size * scale_f)
	box.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.45
	box.material_override = mat
	box.position = Vector3(c2.x, elev + 2.0, c2.y)
	_markers.add_child(box)


func pan_camera(delta: float, input_dir: Vector2) -> void:
	if input_dir == Vector2.ZERO:
		return
	var fwd := -camera.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := camera.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	_camera_target += (right * input_dir.x + fwd * -input_dir.y) * WorldRTS3DConfigLib.CAMERA_PAN_SPEED * delta
	_apply_camera()


func zoom_camera(zoom_in: bool) -> void:
	var step: float = WorldRTS3DConfigLib.CAMERA_ZOOM_STEP
	_camera_height = _camera_height / step if zoom_in else _camera_height * step
	_camera_height = clampf(
		_camera_height,
		WorldRTS3DConfigLib.CAMERA_MIN_HEIGHT,
		WorldRTS3DConfigLib.CAMERA_MAX_HEIGHT,
	)
	_apply_camera()


func _frame_camera() -> void:
	if battle_data == null:
		return
	var contact_x: float = (float(battle_data.contact_column) + 0.5) * battle_data.cell_size
	contact_x -= battle_data.map_size.x * 0.5
	_camera_target = Vector3(contact_x, 0.0, 0.0)
	_camera_height = WorldRTS3DConfigLib.CAMERA_DEFAULT_HEIGHT
	_apply_camera()


func _apply_camera() -> void:
	if camera == null:
		return
	camera.position = _camera_target + Vector3(0.0, _camera_height, _camera_height * 0.55)
	camera.look_at(_camera_target, Vector3.UP)
